import AppKit
import SwiftUI

extension Notification.Name {
    static let quotaWidgetUsagePayloadDidRefresh = Notification.Name("quotaWidgetUsagePayloadDidRefresh")
}

@MainActor
final class QuotaWidgetModel: ObservableObject {
    @Published var status = "等待首次刷新"
    /// Provider rows shown in the status-bar panel, in the Touch Bar's order.
    @Published private(set) var menuRows: [MenuProviderRow] = []
    /// Providers reporting usable figures, for the panel's status pill.
    @Published private(set) var menuConnected = 0
    private var timer: Timer?
    private var hasStarted = false

    /// How often the payload is refreshed while the app runs. The Touch Bar agent
    /// reads this app's mirror, so a stale mirror would show placeholder balances —
    /// keep this well under the agent's freshness window.
    static let refreshInterval: TimeInterval = 300

    /// Rebuilds the panel rows from the shared payload and the configured order.
    func reloadMenuRows() {
        let payload = (try? UsageStore().read())
            .flatMap { try? UsagePayload.decode(Data($0.utf8)) }
        let order = MenuProviderSelection.normalize(AppConfigStore().readMenuProviders())
        menuRows = MenuSummary.rows(from: payload, order: order)
        menuConnected = MenuSummary.connectedCount(from: payload)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        status = "已启动 · 手动刷新"
        reloadMenuRows()
        NotificationCenter.default.addObserver(
            forName: .quotaWidgetUsagePayloadDidRefresh,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadMenuRows() }
        }
        timer?.invalidate()
        // A full refresh: the API-key-only scope deliberately preserves the local
        // agent sections, which left Codex showing a launch-time snapshot.
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAllProviders() }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    nonisolated static func apiKeys(from store: APIKeyStore) throws -> [APIKeyProviderID: String] {
        try store.readAll()
    }

    private nonisolated static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    nonisolated static func siliconFlowConsoleProvider(
        from consoleSession: StoredSiliconFlowConsoleSession?
    ) async -> UsageProvider {
        if let consoleSession, consoleSession.isConfigured {
            return await SiliconFlowConsoleSessionProvider(
                session: consoleSession
            ).fetchBalance()
        }
        if let consoleSession,
           consoleSession.cookieHeader?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           consoleSession.subjectID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return UsageProvider(
                ok: false,
                reason: "invalid_subject",
                kind: "balance",
                source: "console_session",
                live: false
            )
        }
        return UsageProvider(
            ok: false,
            reason: "login_required",
            kind: "balance",
            source: "console_session",
            live: false
        )
    }

    nonisolated static func refreshUsagePayload(
        providerScope: UsageFetcher.ProviderScope = .all
    ) async throws {
        let credentials = (try? AppCredentialBundleStore().snapshot())
            ?? AppCredentialSnapshot(apiKeys: [:], siliconFlowConsoleSession: nil)
        let usageStore = UsageStore()
        let existing = providerScope == .apiKeyOnly ? try? usageStore.read() : nil
        var json = try UsageFetcher.fetch(
            apiKeys: UsageFetcher.mergingExternalCredentials(keychain: credentials.apiKeys),
            providerScope: providerScope
        )
        let consoleProvider = await siliconFlowConsoleProvider(
            from: credentials.siliconFlowConsoleSession
        )
        json = try UsageFetcher.replacingSiliconFlowProvider(
            in: json,
            consoleProvider: consoleProvider
        )
        if providerScope == .apiKeyOnly {
            json = UsageFetcher.preservingLocalAgentProviders(existing: existing, in: json)
        }
        try usageStore.write(json)
    }

    func refresh(providerScope: UsageFetcher.ProviderScope = .apiKeyOnly) {
        status = "正在刷新…"
        Task.detached { [weak self] in
            do {
                try await Self.refreshUsagePayload(providerScope: providerScope)
                await MainActor.run {
                    NotificationCenter.default.post(name: .quotaWidgetUsagePayloadDidRefresh, object: nil)
                    self?.status = "已刷新 \(Date().formatted(date: .omitted, time: .shortened))"
                }
            } catch {
                NSLog("[QuotaWidget] refresh failed: %@", String(describing: error))
                await MainActor.run {
                    self?.status = "刷新失败 · 保留上次数据"
                }
            }
        }
    }

    func refreshAPIKeyProviders() {
        refresh(providerScope: .apiKeyOnly)
    }

    func refreshAllProviders() {
        refresh(providerScope: .all)
    }
}

final class QuotaWidgetAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task.detached {
            do {
                try await QuotaWidgetModel.refreshUsagePayload()
                await MainActor.run {
                    NotificationCenter.default.post(name: .quotaWidgetUsagePayloadDidRefresh, object: nil)
                }
                NSLog("[QuotaWidget] launch refresh completed")
            } catch {
                NSLog("[QuotaWidget] launch refresh failed: %@", String(describing: error))
            }
        }
    }
}

@MainActor
struct SettingsPresenter {
    var activateApplication: () -> Void
    var openSettings: () -> Void
    var raiseSettingsWindow: () -> Void
    var scheduleAfterOpen: (@escaping @MainActor () -> Void) -> Void

    func present() {
        activateApplication()
        openSettings()
        scheduleAfterOpen {
            activateApplication()
            raiseSettingsWindow()
        }
    }

    static func app(openSettings: @escaping () -> Void) -> SettingsPresenter {
        SettingsPresenter(
            activateApplication: {
                NSApplication.shared.setActivationPolicy(.regular)
                NSApplication.shared.activate()
            },
            openSettings: openSettings,
            raiseSettingsWindow: {
                NSApplication.shared.windows
                    .filter { $0.isVisible && $0.canBecomeKey }
                    .forEach {
                        $0.collectionBehavior.insert(.canJoinAllSpaces)
                        $0.makeKeyAndOrderFront(nil)
                        $0.orderFrontRegardless()
                    }
            },
            scheduleAfterOpen: { action in
                DispatchQueue.main.async { action() }
            }
        )
    }
}

@main
struct QuotaWidgetApp: App {
    @NSApplicationDelegateAdaptor(QuotaWidgetAppDelegate.self) private var appDelegate
    @StateObject private var model = QuotaWidgetModel()
    @StateObject private var settingsModel = AccountSettingsViewModel(autoload: false)

    var body: some Scene {
        MenuBarExtra("QuotaWidget", systemImage: "gauge.with.dots.needle.67percent") {
            MenuBarPanelHost(model: model)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: model.status, initial: true) {
            if model.status == "等待首次刷新" { model.start() }
        }

        Settings {
            ControlCenterView(
                accountViewModel: settingsModel,
                refreshNow: { model.refreshAllProviders() }
            )
        }
    }
}
