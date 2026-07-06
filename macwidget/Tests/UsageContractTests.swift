import Foundation
import XCTest
@testable import QuotaWidgetApp

final class UsageContractTests: XCTestCase {
    func testDecodesLiveStaleAndFailedProviders() throws {
        let json = """
        {
          "schema_version": 1,
          "claude": {
            "ok": true, "live": true, "fetched_at": 100,
            "five_h": {"pct": 85, "resets_at": 200},
            "weekly": {"pct": 29, "resets_at": 300}
          },
          "codex": {
            "ok": true, "live": false, "fetched_at": 110, "as_of": 105,
            "five_h": {"pct": 88, "resets_at": 210, "stale": true},
            "weekly": {"pct": 37, "resets_at": 310, "stale": false}
          },
          "kimi": {"ok": false, "reason": "expired", "live": false},
          "deepseek": {
            "ok": true, "kind": "balance", "live": true, "fetched_at": 120,
            "balance": {"amount": 110.0, "currency": "CNY", "available": true, "label": "Balance"},
            "burn_rate": {"amount_per_day": 3.2, "window_days": 7, "estimated_days_left": 34, "confidence": "medium"}
          },
          "siliconflow": {
            "ok": true, "kind": "balance", "live": false, "reason": "stale",
            "balance": {"amount": 88.88, "currency": "CNY", "available": true, "label": "Balance"},
            "burn_rate": {"confidence": "none", "reason": "insufficient_history"}
          },
          "openrouter": {"ok": false, "kind": "balance", "reason": "no_data", "live": false}
        }
        """

        let payload = try UsagePayload.decode(Data(json.utf8))

        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertEqual(payload.claude.fiveH?.percentage, 85)
        XCTAssertTrue(payload.codex.fiveH?.stale == true)
        XCTAssertEqual(payload.kimi.reason, "expired")
        XCTAssertEqual(payload.deepseek.balance?.amount, 110.0)
        XCTAssertEqual(payload.deepseek.burnRate?.estimatedDaysLeft, 34)
        XCTAssertEqual(payload.siliconflow.burnRate?.confidence, "none")
        XCTAssertEqual(payload.openrouter.reason, "no_data")
    }

    func testProviderMessageMatchesSharedFailureLanguage() {
        let provider = UsageProvider(ok: false, reason: "rate_limited")
        XCTAssertEqual(
            ProviderPresentation.message(for: .claude, provider: provider),
            "请求受限 · 稍后自动重试"
        )
    }

    func testMacWidgetUsesBarPrimaryLayoutSource() throws {
        let source = try widgetSource()
        XCTAssertFalse(source.contains("DualRing"), "mac widget should use bar-primary rows, not the old dual-ring view")
        XCTAssertFalse(source.contains("MetricRow"), "mac widget should use bar-primary rows, not the old metric row view")
        XCTAssertTrue(source.contains("UsageBarRow"), "mac widget should render usage providers with bar-primary rows")
        XCTAssertTrue(source.contains("ProviderGridColumn"), "medium widget should use provider columns for all six providers")
    }

    func testMediumWidgetIncludesAllSixProviders() throws {
        let source = try widgetSource()
        let expectedKinds = [
            ".claude", ".codex", ".kimi", ".deepseek", ".siliconflow", ".openrouter"
        ]

        for kind in expectedKinds {
            XCTAssertTrue(source.contains("ProviderGridColumn(kind: \(kind)"), "medium widget is missing \(kind)")
        }
    }

    func testBalancePresentationFormatting() {
        let balance = BalanceInfo(amount: 24.58, currency: "USD", available: true, label: "Balance")
        let burn = BurnRateInfo(
            amountPerDay: 1.0,
            windowDays: 7,
            estimatedDaysLeft: 24,
            confidence: "medium",
            reason: nil
        )
        XCTAssertEqual(ProviderPresentation.balanceAmount(balance), "$24.58")
        XCTAssertFalse(ProviderPresentation.balanceTrend(burn).isEmpty)
    }

    func testFetcherEnvironmentIncludesConfiguredAPIKeys() {
        let env = UsageFetcher.environment(
            base: ["PATH": "/usr/bin"],
            apiKeys: [.deepseek: "deepseek-key", .openrouter: "openrouter-key"]
        )

        XCTAssertEqual(env["PATH"], "/usr/bin")
        XCTAssertEqual(env["DEEPSEEK_API_KEY"], "deepseek-key")
        XCTAssertEqual(env["OPENROUTER_API_KEY"], "openrouter-key")
        XCTAssertNil(env["SILICONFLOW_API_KEY"])
    }

    func testProviderStatusFromJSONSanitizesValues() throws {
        let json = """
        {
          "schema_version": 1,
          "deepseek": {
            "ok": true, "kind": "balance", "live": true, "fetched_at": 120,
            "balance": {"amount": 110.0, "currency": "CNY", "available": true, "label": "Balance"}
          }
        }
        """
        let provider = UsageFetcher.providerStatus(from: json, providerKey: "deepseek")
        XCTAssertEqual(provider?.balance?.amount, 110.0)
        XCTAssertNil(UsageFetcher.providerStatus(from: json, providerKey: "siliconflow"))
    }

    func testAccountRowsIncludeAllSixProviders() {
        let model = AccountSettingsModel(
            payload: .preview,
            configuredAPIKeys: [.siliconflow],
            codexActiveRefresh: false
        )

        XCTAssertEqual(model.rows.map(\.id), [
            .claude, .codex, .kimi, .deepseek, .siliconflow, .openrouter
        ])
    }

    func testAccountRowsClassifyProviderKinds() {
        let model = AccountSettingsModel(
            payload: .preview,
            configuredAPIKeys: [.deepseek, .openrouter],
            codexActiveRefresh: false
        )

        let byID = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.id, $0) })
        XCTAssertEqual(byID[.claude]?.kind, .localAgent)
        XCTAssertEqual(byID[.codex]?.kind, .localAgent)
        XCTAssertEqual(byID[.kimi]?.kind, .localAgent)
        XCTAssertEqual(byID[.deepseek]?.kind, .apiKey)
        XCTAssertEqual(byID[.siliconflow]?.kind, .apiKey)
        XCTAssertEqual(byID[.openrouter]?.kind, .apiKey)
    }

    func testAccountRowsReflectConfiguredAPIKeysAndStatus() {
        let model = AccountSettingsModel(
            payload: .preview,
            configuredAPIKeys: [.siliconflow],
            codexActiveRefresh: false
        )

        let byID = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.id, $0) })
        XCTAssertFalse(byID[.deepseek]?.configured ?? true)
        XCTAssertTrue(byID[.siliconflow]?.configured ?? false)
        XCTAssertFalse(byID[.openrouter]?.configured ?? true)
        XCTAssertEqual(byID[.siliconflow]?.statusText, ProviderPresentation.cachedBalanceMessage())
    }

    func testCodexRowReflectsActiveRefreshFlag() {
        let enabled = AccountSettingsModel(
            payload: .preview,
            configuredAPIKeys: [],
            codexActiveRefresh: true
        )
        let disabled = AccountSettingsModel(
            payload: .preview,
            configuredAPIKeys: [],
            codexActiveRefresh: false
        )

        let enabledRow = enabled.rows.first { $0.id == .codex }
        let disabledRow = disabled.rows.first { $0.id == .codex }
        XCTAssertTrue(enabledRow?.configured ?? false)
        XCTAssertFalse(disabledRow?.configured ?? true)
    }

    func testCollectsOnlyConfiguredAPIKeys() throws {
        let backend = InMemoryCredentialBackend()
        let store = APIKeyStore(backend: backend)
        try store.save("sf-key", for: .siliconflow)

        let keys = try QuotaWidgetModel.apiKeys(from: store)

        XCTAssertEqual(keys, [.siliconflow: "sf-key"])
    }

    @MainActor
    func testSaveKeyReturnsSuccessAndReloadsConfiguredProvider() throws {
        let backend = InMemoryCredentialBackend()
        let viewModel = AccountSettingsViewModel(
            apiKeyStore: APIKeyStore(backend: backend),
            configStore: AppConfigStore(
                baseDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            usageStore: UsageStore(containerURLProvider: {
                FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            })
        )

        viewModel.beginEdit(.deepseek)
        viewModel.keyInput = "  deepseek-key  "

        XCTAssertTrue(viewModel.saveKey())
        XCTAssertNil(viewModel.editingProvider)
        XCTAssertEqual(viewModel.saveErrorText, nil)
        XCTAssertEqual(try backend.read(service: APIKeyStore.defaultService, account: "deepseek"), "deepseek-key")
        XCTAssertTrue(viewModel.model.configuredAPIKeys.contains(.deepseek))
    }

    @MainActor
    func testSaveKeyKeepsSheetOpenAndShowsErrorWhenCredentialStoreFails() {
        let viewModel = AccountSettingsViewModel(
            apiKeyStore: APIKeyStore(backend: FailingCredentialBackend()),
            configStore: AppConfigStore(
                baseDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            usageStore: UsageStore(containerURLProvider: {
                FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            })
        )

        viewModel.beginEdit(.openrouter)
        viewModel.keyInput = "openrouter-key"

        XCTAssertFalse(viewModel.saveKey())
        XCTAssertEqual(viewModel.editingProvider, .openrouter)
        XCTAssertEqual(viewModel.saveErrorText, "保存失败：forced failure")
        XCTAssertFalse(viewModel.model.configuredAPIKeys.contains(.openrouter))
    }

    @MainActor
    func testSettingsPresenterActivatesAppBeforeOpeningSettingsAndRaisesWindowAfterwards() {
        var events: [String] = []
        let presenter = SettingsPresenter(
            activateApplication: { events.append("activate") },
            openSettings: { events.append("open") },
            raiseSettingsWindow: { events.append("raise") },
            scheduleAfterOpen: { action in action() }
        )

        presenter.present()

        XCTAssertEqual(events, ["activate", "open", "activate", "raise"])
    }

    @MainActor
    func testTestProvidersUsesInjectedStores() async throws {
        // Given: an injected API key store with a DeepSeek key.
        let apiBackend = InMemoryCredentialBackend()
        let apiKeyStore = APIKeyStore(backend: apiBackend)
        try apiKeyStore.save("injected-key", for: .deepseek)

        // Given: an injected usage store in a temp directory.
        let usageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let usageStore = UsageStore(containerURLProvider: { usageDirectory })

        // Given: a fake fetch script that validates the injected key is passed
        // and returns valid usage JSON.
        let scriptDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: scriptDirectory,
            withIntermediateDirectories: true
        )
        let scriptURL = scriptDirectory.appendingPathComponent("fetch_usage.py")
        let script = """
        import json, os, sys
        key = os.environ.get("DEEPSEEK_API_KEY", "NONE")
        if key != "injected-key":
            sys.stderr.write("expected injected-key, got: %s\\n" % key)
            sys.exit(1)
        print(json.dumps({"schema_version": 1, "claude": {"ok": False}, "codex": {"ok": False}, "kimi": {"ok": False}, "deepseek": {"ok": True, "kind": "balance", "live": True, "fetched_at": 1, "balance": {"amount": 42.0, "currency": "CNY", "available": True, "label": "Balance"}}, "siliconflow": {"ok": False}, "openrouter": {"ok": False}}))
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        setenv("QUOTAWIDGET_FETCH", scriptURL.path, 1)
        defer {
            unsetenv("QUOTAWIDGET_FETCH")
            try? FileManager.default.removeItem(at: scriptDirectory)
            try? FileManager.default.removeItem(at: usageDirectory)
        }

        let configDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configStore = AppConfigStore(baseDirectory: configDirectory)

        let viewModel = AccountSettingsViewModel(
            apiKeyStore: apiKeyStore,
            configStore: configStore,
            usageStore: usageStore
        )

        // When: refresh providers using the injected stores.
        viewModel.testProviders()

        // Then: wait for the async work to finish while yielding the main actor
        // so the view model's MainActor continuation can run.
        let start = Date()
        while viewModel.isTesting && Date().timeIntervalSince(start) < 5 {
            await Task.yield()
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertFalse(viewModel.isTesting, "testProviders should complete within timeout")

        let deepseekRow = viewModel.model.rows.first { $0.id == .deepseek }
        XCTAssertNotNil(
            deepseekRow?.balanceSummary,
            "Injected usage store should receive the fetched JSON"
        )
        XCTAssertTrue(
            deepseekRow?.balanceSummary?.contains("¥42.00") ?? false,
            "Injected API key store should supply the key to the fetch"
        )
    }

    func testAPIKeyStoreUsesStableServiceAndProviderAccounts() {
        XCTAssertEqual(APIKeyStore.defaultService, "AI Agent Usage Widget")
        XCTAssertEqual(APIKeyProviderID.deepseek.rawValue, "deepseek")
        XCTAssertEqual(APIKeyProviderID.siliconflow.rawValue, "siliconflow")
        XCTAssertEqual(APIKeyProviderID.openrouter.rawValue, "openrouter")
    }

    func testControlCenterDefinesExpectedTabs() throws {
        let source = try sourceFile("App/ControlCenterView.swift")

        XCTAssertTrue(source.contains("TabView"))
        XCTAssertTrue(source.contains("Accounts"))
        XCTAssertTrue(source.contains("Refresh"))
        XCTAssertTrue(source.contains("Displays"))
        XCTAssertTrue(source.contains("Diagnostics"))
        XCTAssertTrue(source.contains("AccountSettingsView"))
        XCTAssertTrue(source.contains("DisplayLayerStore"))
    }

    func testSettingsMenuOpensControlCenter() throws {
        let source = try sourceFile("App/QuotaWidgetApp.swift")

        XCTAssertTrue(source.contains("ControlCenterView"))
        XCTAssertTrue(source.contains("Settings..."))
        XCTAssertTrue(source.contains("SettingsPresenter"))
    }

    func testAccountRowsKeepAPIProvidersInControlApp() {
        let model = AccountSettingsModel(
            payload: .preview,
            configuredAPIKeys: [.deepseek, .siliconflow],
            codexActiveRefresh: false
        )

        let apiRows = model.rows.filter { $0.kind == .apiKey }
        XCTAssertEqual(apiRows.map(\.id), [.deepseek, .siliconflow, .openrouter])
        XCTAssertEqual(apiRows.map(\.configured), [true, true, false])
    }
}

private func widgetSource() throws -> String {
    try sourceFile("Widget/QuotaWidget.swift")
}

private func sourceFile(_ relativePath: String) throws -> String {
    var directory = URL(fileURLWithPath: #filePath)
    while directory.lastPathComponent != "macwidget" {
        let parent = directory.deletingLastPathComponent()
        if parent.path == directory.path {
            throw NSError(
                domain: "UsageContractTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not locate macwidget directory"]
            )
        }
        directory = parent
    }
    return try String(contentsOf: directory.appendingPathComponent(relativePath), encoding: .utf8)
}

private struct FailingCredentialBackend: CredentialBackend {
    func read(service: String, account: String) throws -> String? { nil }
    func save(_ value: String, service: String, account: String) throws {
        throw FailingCredentialError()
    }
    func delete(service: String, account: String) throws {}
}

private struct FailingCredentialError: Error, CustomStringConvertible {
    var description: String { "forced failure" }
}
