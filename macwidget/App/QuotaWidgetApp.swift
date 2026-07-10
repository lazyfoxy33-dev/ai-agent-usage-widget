import AppKit
import SwiftUI
import WidgetKit

extension Notification.Name {
    static let quotaWidgetUsagePayloadDidRefresh = Notification.Name("quotaWidgetUsagePayloadDidRefresh")
}

@MainActor
final class QuotaWidgetModel: ObservableObject {
    @Published var status = "等待首次刷新"
    private var timer: Timer?
    private var lastUsed: String?
    private var hasStarted = false

    init() {
        self.lastUsed = UserDefaults.standard.string(forKey: "lastUsedProvider")
        startForegroundTracking()
        if !Self.isRunningUnitTests {
            start()
        }
    }

    func startForegroundTracking() {
        updateActive(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    @objc private func activeAppChanged() {
        updateActive(NSWorkspace.shared.frontmostApplication)
    }

    private func updateActive(_ app: NSRunningApplication?) {
        let tag = providerTag(app)
        if let tag { lastUsed = tag; UserDefaults.standard.set(tag, forKey: "lastUsedProvider") }
        let active = tag ?? lastUsed ?? "claude"
        try? UsageStore().writeActive(active)
    }

    private func providerTag(_ app: NSRunningApplication?) -> String? {
        guard let app else { return nil }
        let s = ((app.bundleIdentifier ?? "") + " " + (app.localizedName ?? "")).lowercased()
        if s.contains("claude") { return "claude" }
        if s.contains("kimi") || s.contains("moonshot") { return "kimi" }
        if s.contains("codex") || s.contains("openai") || s.contains("chatgpt") { return "codex" }
        return nil
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    nonisolated static func apiKeys(from store: APIKeyStore) throws -> [APIKeyProviderID: String] {
        try store.readAll()
    }

    private nonisolated static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    nonisolated static func refreshUsagePayload() async throws {
        let credentials = (try? AppCredentialBundleStore().snapshot())
            ?? AppCredentialSnapshot(apiKeys: [:], siliconFlowConsoleSession: nil)
        var json = try UsageFetcher.fetch(apiKeys: credentials.apiKeys)
        if let consoleSession = credentials.siliconFlowConsoleSession,
           consoleSession.isConfigured {
            let consoleProvider = await SiliconFlowConsoleSessionProvider(
                session: consoleSession
            ).fetchBalance()
            json = try UsageFetcher.replacingSiliconFlowProvider(
                in: json,
                consoleProvider: consoleProvider
            )
        } else if let consoleSession = credentials.siliconFlowConsoleSession,
                  consoleSession.cookieHeader?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  consoleSession.subjectID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            json = try UsageFetcher.replacingSiliconFlowProvider(
                in: json,
                consoleProvider: UsageProvider(
                    ok: false,
                    reason: "invalid_subject",
                    kind: "balance",
                    source: "console_session",
                    live: false
                )
            )
        } else {
            json = try UsageFetcher.replacingSiliconFlowProvider(
                in: json,
                consoleProvider: UsageProvider(
                    ok: false,
                    reason: "login_required",
                    kind: "balance",
                    source: "console_session",
                    live: false
                )
            )
        }
        try UsageStore().write(json)
    }

    func refresh() {
        status = "正在刷新…"
        Task.detached { [weak self] in
            do {
                try await Self.refreshUsagePayload()
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

struct MenuBarContentView: View {
    @ObservedObject var model: QuotaWidgetModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(model.status)
        Divider()
        Button("Settings...") { SettingsPresenter.app(openSettings: { openSettings() }).present() }
        Button("立即刷新") { model.refresh() }
        Divider()
        Button("退出") { NSApplication.shared.terminate(nil) }
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
    @StateObject private var settingsModel = AccountSettingsViewModel()

    var body: some Scene {
        MenuBarExtra("QuotaWidget", systemImage: "gauge.with.dots.needle.67percent") {
            MenuBarContentView(model: model)
        }
        .onChange(of: model.status, initial: true) {
            if model.status == "等待首次刷新" { model.start() }
        }

        Settings {
            let displayStore = DisplayLayerStore(
                installStateDirectory: DisplayLayerStore.defaultInstallStateDirectory()
            )
            ControlCenterView(
                accountViewModel: settingsModel,
                displayStore: displayStore,
                usageStore: UsageStore(),
                refreshNow: { model.refresh() },
                displayActions: DisplayLayerActions(
                    installUbersicht: { try displayStore.installBundledUbersichtWidget() },
                    openUbersichtFolder: { try displayStore.openUbersichtWidgetsDirectory() },
                    refreshWidgetKit: { WidgetCenter.shared.reloadAllTimelines() },
                    openWidgetGallery: {
                        let settings = URL(fileURLWithPath: "/System/Applications/System Settings.app")
                        guard NSWorkspace.shared.open(settings) else {
                            throw DisplayLayerStoreError.openFailed(settings)
                        }
                    },
                    installTouchBar: { try displayStore.installTouchBar() },
                    openTouchBar: { try displayStore.openTouchBarApp() }
                )
            )
        }
    }
}
