import AppKit
import SwiftUI
import WidgetKit

@MainActor
final class QuotaWidgetModel: ObservableObject {
    @Published var status = "等待首次刷新"
    private var timer: Timer?
    private var lastUsed: String?

    init() {
        self.lastUsed = UserDefaults.standard.string(forKey: "lastUsedProvider")
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
        WidgetCenter.shared.reloadAllTimelines()
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
        status = "已启动 · 手动刷新"
    }

    nonisolated static func apiKeys(from store: APIKeyStore) throws -> [APIKeyProviderID: String] {
        var keys: [APIKeyProviderID: String] = [:]
        for provider in APIKeyProviderID.allCases {
            if let value = try store.read(provider) {
                keys[provider] = value
            }
        }
        return keys
    }

    func refresh(providerScope: UsageFetcher.ProviderScope = .apiKeyOnly) {
        status = "正在刷新…"
        Task.detached { [weak self] in
            do {
                let store = APIKeyStore()
                let keys = (try? QuotaWidgetModel.apiKeys(from: store)) ?? [:]
                let json = try UsageFetcher.fetch(apiKeys: keys, providerScope: providerScope)
                let usageStore = UsageStore()
                let merged = providerScope == .apiKeyOnly
                    ? UsageFetcher.preservingLocalAgentProviders(existing: try? usageStore.read(), in: json)
                    : json
                try usageStore.write(merged)
                await MainActor.run {
                    WidgetCenter.shared.reloadAllTimelines()
                    self?.status = "已刷新 \(Date().formatted(date: .omitted, time: .shortened))"
                }
            } catch {
                await MainActor.run {
                    self?.status = "刷新失败 · 保留上次数据"
                }
            }
        }
    }

    func refreshAPIKeyProviders() {
        refresh(providerScope: .apiKeyOnly)
    }
}

struct MenuBarContentView: View {
    @ObservedObject var model: QuotaWidgetModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(model.status)
        Divider()
        Button("Settings...") { SettingsPresenter.app(openSettings: { openSettings() }).present() }
        Button("立即刷新") { model.refreshAPIKeyProviders() }
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
    @StateObject private var model = QuotaWidgetModel()
    @StateObject private var settingsModel = AccountSettingsViewModel(autoload: false)

    var body: some Scene {
        MenuBarExtra("QuotaWidget", systemImage: "gauge.with.dots.needle.67percent") {
            MenuBarContentView(model: model)
        }
        .onChange(of: model.status, initial: true) {
            if model.status == "等待首次刷新" { model.start() }
        }

        Settings {
            let displayStore = DisplayLayerStore()
            ControlCenterView(
                accountViewModel: settingsModel,
                displayStore: displayStore,
                usageStore: UsageStore(),
                refreshNow: { model.refreshAPIKeyProviders() },
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
