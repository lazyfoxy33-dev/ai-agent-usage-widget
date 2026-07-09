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
        XCTAssertTrue(
            [
                "请求受限 · 稍后自动重试",
                "Rate limited · retrying soon"
            ].contains(ProviderPresentation.message(for: .claude, provider: provider))
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

    func testDecodesProviderSource() throws {
        let json = """
        {
          "ok": true,
          "kind": "balance",
          "source": "console_session",
          "balance": {"amount": 0, "currency": "CNY", "available": true, "label": "Console Balance"}
        }
        """

        let provider = try JSONDecoder().decode(UsageProvider.self, from: Data(json.utf8))

        XCTAssertEqual(provider.source, "console_session")
    }

    func testBalanceUnavailableAndLoginRequiredMessages() {
        XCTAssertTrue(
            [
                "余额口径异常 · 请到后台核对",
                "Balance unavailable · check provider console"
            ].contains(ProviderPresentation.message(
                for: .siliconflow,
                provider: UsageProvider(ok: false, reason: "balance_unavailable", kind: "balance")
            ))
        )
        XCTAssertTrue(
            [
                "需要重新登录 SiliconFlow 后台",
                "Sign in to SiliconFlow console again"
            ].contains(ProviderPresentation.message(
                for: .siliconflow,
                provider: UsageProvider(ok: false, reason: "login_required", kind: "balance")
            ))
        )
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

    func testReplacingProviderPreservesSharedPayloadShape() throws {
        let json = """
        {
          "schema_version": 1,
          "claude": {"ok": false},
          "codex": {"ok": false},
          "kimi": {"ok": false},
          "deepseek": {"ok": false},
          "siliconflow": {"ok": false, "kind": "balance", "reason": "balance_unavailable"},
          "openrouter": {"ok": false}
        }
        """
        let consoleProvider = UsageProvider(
            ok: true,
            kind: "balance",
            source: "console_session",
            live: true,
            balance: BalanceInfo(amount: 0, currency: "CNY", available: true, label: "Console Balance")
        )

        let merged = try UsageFetcher.replacingProvider(
            in: json,
            providerKey: "siliconflow",
            provider: consoleProvider
        )
        let decoded = try UsagePayload.decode(Data(merged.utf8))

        XCTAssertTrue(decoded.siliconflow.ok)
        XCTAssertEqual(decoded.siliconflow.source, "console_session")
        XCTAssertEqual(decoded.siliconflow.balance?.label, "Console Balance")
    }

    func testSiliconFlowConsoleFailureDoesNotFallbackToAPIKeyBalance() throws {
        let json = """
        {
          "schema_version": 1,
          "claude": {"ok": false},
          "codex": {"ok": false},
          "kimi": {"ok": false},
          "deepseek": {"ok": false},
          "siliconflow": {
            "ok": true,
            "kind": "balance",
            "source": "api_key",
            "live": true,
            "balance": {"amount": 12, "currency": "CNY", "available": true, "label": "Balance"}
          },
          "openrouter": {"ok": false}
        }
        """
        let consoleProvider = UsageProvider(
            ok: false,
            reason: "error",
            kind: "balance",
            source: "console_session",
            live: false
        )

        let merged = try UsageFetcher.replacingSiliconFlowProvider(
            in: json,
            consoleProvider: consoleProvider
        )
        let decoded = try UsagePayload.decode(Data(merged.utf8))

        XCTAssertFalse(decoded.siliconflow.ok)
        XCTAssertEqual(decoded.siliconflow.source, "console_session")
        XCTAssertNil(decoded.siliconflow.balance)
    }

    func testSiliconFlowConsoleSuccessOverridesAPIKeyBalance() throws {
        let json = """
        {
          "schema_version": 1,
          "claude": {"ok": false},
          "codex": {"ok": false},
          "kimi": {"ok": false},
          "deepseek": {"ok": false},
          "siliconflow": {"ok": false, "kind": "balance", "reason": "balance_unavailable"},
          "openrouter": {"ok": false}
        }
        """
        let consoleProvider = UsageProvider(
            ok: true,
            kind: "balance",
            source: "console_session",
            live: true,
            balance: BalanceInfo(amount: 96, currency: "CNY", available: true, label: "Console Balance")
        )

        let merged = try UsageFetcher.replacingSiliconFlowProvider(
            in: json,
            consoleProvider: consoleProvider
        )
        let decoded = try UsagePayload.decode(Data(merged.utf8))

        XCTAssertTrue(decoded.siliconflow.ok)
        XCTAssertEqual(decoded.siliconflow.source, "console_session")
        XCTAssertEqual(decoded.siliconflow.balance?.amount, 96)
    }

    func testSiliconFlowZeroConsoleDoesNotFallbackToPositiveAPIKeyBalance() throws {
        let json = """
        {
          "schema_version": 1,
          "claude": {"ok": false},
          "codex": {"ok": false},
          "kimi": {"ok": false},
          "deepseek": {"ok": false},
          "siliconflow": {
            "ok": true,
            "kind": "balance",
            "source": "api_key",
            "live": true,
            "balance": {"amount": 88, "currency": "CNY", "available": true, "label": "Balance"}
          },
          "openrouter": {"ok": false}
        }
        """
        let consoleProvider = UsageProvider(
            ok: true,
            kind: "balance",
            source: "console_session",
            live: true,
            balance: BalanceInfo(amount: 0, currency: "CNY", available: true, label: "Console Balance")
        )

        let merged = try UsageFetcher.replacingSiliconFlowProvider(
            in: json,
            consoleProvider: consoleProvider
        )
        let decoded = try UsagePayload.decode(Data(merged.utf8))

        XCTAssertTrue(decoded.siliconflow.ok)
        XCTAssertEqual(decoded.siliconflow.source, "console_session")
        XCTAssertEqual(decoded.siliconflow.balance?.amount, 0)
    }

    func testSiliconFlowZeroConsoleKeepsZeroWhenAPIKeyIsAlsoZero() throws {
        let json = """
        {
          "schema_version": 1,
          "claude": {"ok": false},
          "codex": {"ok": false},
          "kimi": {"ok": false},
          "deepseek": {"ok": false},
          "siliconflow": {
            "ok": true,
            "kind": "balance",
            "source": "api_key",
            "live": true,
            "balance": {"amount": 0, "currency": "CNY", "available": true, "label": "Balance"}
          },
          "openrouter": {"ok": false}
        }
        """
        let consoleProvider = UsageProvider(
            ok: true,
            kind: "balance",
            source: "console_session",
            live: true,
            balance: BalanceInfo(amount: 0, currency: "CNY", available: true, label: "Console Balance")
        )

        let merged = try UsageFetcher.replacingSiliconFlowProvider(
            in: json,
            consoleProvider: consoleProvider
        )
        let decoded = try UsagePayload.decode(Data(merged.utf8))

        XCTAssertTrue(decoded.siliconflow.ok)
        XCTAssertEqual(decoded.siliconflow.source, "console_session")
        XCTAssertEqual(decoded.siliconflow.balance?.amount, 0)
    }

    func testAccountRowsIncludeAllSixProviders() {
        let model = AccountSettingsModel(
            payload: .preview,
            configuredAPIKeys: [],
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
            configuredAPIKeys: [],
            codexActiveRefresh: false,
            siliconFlowConsoleConfigured: true
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
        try store.save("deepseek-key", for: .deepseek)
        try store.save("openrouter-key", for: .openrouter)

        let keys = try QuotaWidgetModel.apiKeys(from: store)

        XCTAssertEqual(keys, [.deepseek: "deepseek-key", .openrouter: "openrouter-key"])
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
        let rawBundle = try XCTUnwrap(backend.read(
            service: AppCredentialBundleStore.service,
            account: AppCredentialBundleStore.account
        ))
        let bundle = try JSONDecoder().decode(AppCredentialBundle.self, from: Data(rawBundle.utf8))
        XCTAssertEqual(bundle.apiKeys["deepseek"], "deepseek-key")
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
        XCTAssertEqual(APIKeyProviderID.allCases, [.deepseek, .openrouter])
        XCTAssertEqual(APIKeyProviderID.deepseek.rawValue, "deepseek")
        XCTAssertEqual(APIKeyProviderID.openrouter.rawValue, "openrouter")
    }

    func testSiliconFlowConsoleSessionStoreUsesSeparateNamespace() throws {
        let backend = InMemoryCredentialBackend()
        let store = SiliconFlowConsoleSessionStore(backend: backend)

        try store.saveCookieHeader("sf_session=test")
        try store.saveSubjectID("subject-test-123456")

        XCTAssertEqual(try store.readCookieHeader(), "sf_session=test")
        XCTAssertEqual(try store.readSubjectID(), "subject-test-123456")
        XCTAssertNil(try backend.read(service: APIKeyStore.defaultService, account: "siliconflow-console"))
    }

    func testSiliconFlowConsoleSessionRejectsTooShortSubjectID() {
        let session = StoredSiliconFlowConsoleSession(
            cookieHeader: "sf_session=test",
            subjectID: "short"
        )

        XCTAssertFalse(session.isConfigured)
    }

    func testSiliconFlowConsoleProviderAllowlist() {
        XCTAssertTrue(SiliconFlowConsoleSessionProvider.isAllowedProfileURL(
            URL(string: "https://cloud.siliconflow.cn/walletd-server/api/v1/subject/profile/peek")!
        ))
        XCTAssertFalse(SiliconFlowConsoleSessionProvider.isAllowedProfileURL(
            URL(string: "https://cloud.siliconflow.cn/walletd-server/api/v1/subject/profile/peek/extra")!
        ))
        XCTAssertFalse(SiliconFlowConsoleSessionProvider.isAllowedProfileURL(
            URL(string: "https://walletd.siliconflow.cn/api/v1/subject/profile/peek")!
        ))
    }

    func testSiliconFlowConsoleProviderFetchesBalance() async throws {
        let backend = InMemoryCredentialBackend()
        let store = SiliconFlowConsoleSessionStore(backend: backend)
        try store.saveCookieHeader("sf_session=test")
        try store.saveSubjectID("subject-test-123456")
        let provider = SiliconFlowConsoleSessionProvider(
            sessionStore: store,
            fetchData: { request in
                XCTAssertEqual(
                    request.url?.absoluteString,
                    "https://cloud.siliconflow.cn/walletd-server/api/v1/subject/profile/peek"
                )
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Subject-Id"), "subject-test-123456")
                let data = Data("""
                {"data": {"financialInfo": {"chargeBalance": "96", "currency": "CNY"}}}
                """.utf8)
                return (data, HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!)
            }
        )

        let result = await provider.fetchBalance()

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.balance?.amount, 96)
    }

    func testSiliconFlowConsoleProviderReportsInvalidSubject() async throws {
        let backend = InMemoryCredentialBackend()
        let store = SiliconFlowConsoleSessionStore(backend: backend)
        try store.saveCookieHeader("sf_session=test")
        try store.saveSubjectID("subject-test-123456")
        let provider = SiliconFlowConsoleSessionProvider(
            sessionStore: store,
            fetchData: { request in
                let data = Data("""
                {"code": 10001, "message": "validate error: invalid parameter: SubjectId"}
                """.utf8)
                return (data, HTTPURLResponse(
                    url: request.url!,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: nil
                )!)
            }
        )

        let result = await provider.fetchBalance()

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.reason, "invalid_subject")
    }

    func testSiliconFlowConsoleProviderParsesFinancialInfo() throws {
        let data = Data("""
        {
          "data": {
            "financialInfo": {
              "balance": "0",
              "currency": "CNY"
            }
          }
        }
        """.utf8)

        let provider = try SiliconFlowConsoleSessionProvider.parseProfileData(data)

        XCTAssertTrue(provider.ok)
        XCTAssertEqual(provider.source, "console_session")
        XCTAssertEqual(provider.balance?.amount, 0)
        XCTAssertEqual(provider.balance?.label, "Console Balance")
    }

    func testSiliconFlowConsoleProviderPrefersRechargeBalance() throws {
        let data = Data("""
        {
          "data": {
            "financialInfo": {
              "balance": null,
              "totalBalance": "-70",
              "chargeBalance": "96",
              "currency": "CNY"
            }
          }
        }
        """.utf8)

        let provider = try SiliconFlowConsoleSessionProvider.parseProfileData(data)

        XCTAssertEqual(provider.balance?.amount, 96)
    }

    func testSiliconFlowConsoleProviderNormalizesRawBalanceUnits() throws {
        let data = Data("""
        {"data": {"financialInfo": {"balance": "81208061100000"}}}
        """.utf8)

        let provider = try SiliconFlowConsoleSessionProvider.parseProfileData(data)

        XCTAssertEqual(provider.balance?.amount ?? 0, 81.2080611, accuracy: 0.0000001)
    }

    func testSiliconFlowConsoleProviderRejectsNegativeFinancialInfo() throws {
        let data = Data("""
        {"data": {"financialInfo": {"balance": "-1"}}}
        """.utf8)

        XCTAssertThrowsError(try SiliconFlowConsoleSessionProvider.parseProfileData(data))
    }

    func testControlCenterHasTwoColumnLayoutWithNavigation() throws {
        let source = try sourceFile("App/ControlCenterView.swift")

        XCTAssertFalse(source.contains("TabView"), "should use sidebar layout instead of TabView")
        XCTAssertTrue(
            source.contains("ControlSidebar") || source.contains("ControlPage") || source.contains("sidebar"),
            "should have sidebar/navigation structure"
        )
        XCTAssertTrue(source.contains("Accounts"))
        XCTAssertTrue(source.contains("Refresh"))
        XCTAssertTrue(source.contains("Displays"))
        XCTAssertTrue(source.contains("Diagnostics"))
    }

    func testControlCenterContainsGroupLabelsAndProviders() throws {
        let source = try sourceFile("App/ControlCenterView.swift")

        XCTAssertTrue(source.contains("Local Agents"), "should show Local Agents group")
        XCTAssertTrue(source.contains("API Balance"), "should show API Balance group")

        XCTAssertTrue(source.contains("Claude"), "should show Claude provider")
        XCTAssertTrue(source.contains("Codex"), "should show Codex provider")
        XCTAssertTrue(source.contains("Kimi Code"), "should show Kimi Code provider")
        XCTAssertTrue(source.contains("DeepSeek"), "should show DeepSeek provider")
        XCTAssertTrue(source.contains("SiliconFlow"), "should show SiliconFlow provider")
        XCTAssertTrue(source.contains("OpenRouter"), "should show OpenRouter provider")
    }

    func testSiliconFlowConfigurationIsOneCombinedRow() throws {
        let source = try sourceFile("App/ControlCenterView.swift")
        let rowStart = source.range(of: "struct SiliconFlowProviderRow: View")!.lowerBound
        let rowEnd = source.range(of: "struct SourceOptionBadge: View")!.lowerBound
        let rowSource = String(source[rowStart..<rowEnd])

        XCTAssertTrue(source.contains("SiliconFlowProviderRow"), "SiliconFlow should have one console-selected row")
        XCTAssertFalse(rowSource.contains("onEditAPIKey"), "SiliconFlow should not expose an API key action")
        XCTAssertFalse(rowSource.contains("API Key"), "SiliconFlow should not advertise API-key mode")
        XCTAssertFalse(source.contains("SiliconFlowConsoleSessionRow"), "Console session should not render as a separate provider row")
        XCTAssertFalse(source.contains("SiliconFlow Console Balance"), "Console balance should be an option inside SiliconFlow, not a separate provider")
        XCTAssertTrue(source.contains("subjectId"), "Console session save should capture the SiliconFlow subject id")
        XCTAssertTrue(source.contains("SF_SUBJECT_ID"), "Console session save should prefer SiliconFlow's explicit subject global")
        XCTAssertFalse(source.contains("prefill_subject_id"), "Console session save should not persist short prefill subject codes")
    }

    func testSiliconFlowReconnectCapturesSubjectCandidatesFromWebRequests() throws {
        let source = try sourceFile("App/ControlCenterView.swift")

        XCTAssertTrue(source.contains("__quotaWidgetSubjectCandidates"))
        XCTAssertTrue(source.contains("WKUserScript"))
        XCTAssertTrue(source.contains("performance.getEntriesByType"))
    }

    func testDisplaysPanelExposesDisplayLayerActions() throws {
        let source = try sourceFile("App/ControlCenterView.swift")

        XCTAssertTrue(source.contains("DisplayLayerActions"))
        XCTAssertTrue(source.contains("Install / Update"))
        XCTAssertTrue(source.contains("Open Folder"))
        XCTAssertTrue(source.contains("Refresh Timelines"))
        XCTAssertTrue(source.contains("Open Widget Gallery"))
        XCTAssertTrue(source.contains("Open App"))
    }

    func testDisplaysPanelDoesNotSynchronouslyQueryStatusInBody() throws {
        let source = try sourceFile("App/ControlCenterView.swift")
        let displaysStart = source.range(of: "struct DisplaysPage: View")!.lowerBound
        let displayCardStart = source.range(of: "struct DisplayCard")!.lowerBound
        let displaysSource = String(source[displaysStart..<displayCardStart])

        XCTAssertFalse(displaysSource.contains("displayStore.status(for:"))
        XCTAssertTrue(displaysSource.contains("@State private var statuses"))
    }

    func testAppBundlesDisplayLayerInstallSources() throws {
        let project = try sourceFile("QuotaWidget.xcodeproj/project.pbxproj")
        let projectYAML = try sourceFile("project.yml")

        XCTAssertTrue(project.contains("Bundle display layers"))
        XCTAssertTrue(project.contains("../usage-widget"))
        XCTAssertTrue(project.contains("../touchbar"))
        XCTAssertTrue(projectYAML.contains("Bundle display layers"))
        XCTAssertTrue(projectYAML.contains("../usage-widget"))
        XCTAssertTrue(projectYAML.contains("../touchbar"))
    }

    func testSettingsMenuOpensControlCenter() throws {
        let source = try sourceFile("App/QuotaWidgetApp.swift")

        XCTAssertTrue(source.contains("ControlCenterView"))
        XCTAssertTrue(source.contains("Settings..."))
        XCTAssertTrue(source.contains("SettingsPresenter"))
        XCTAssertTrue(source.contains("setActivationPolicy(.regular)"))
    }

    func testAccountRowsKeepAPIProvidersInControlApp() {
        let model = AccountSettingsModel(
            payload: .preview,
            configuredAPIKeys: [.deepseek],
            codexActiveRefresh: false,
            siliconFlowConsoleConfigured: true
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
