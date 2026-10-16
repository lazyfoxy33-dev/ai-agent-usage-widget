import Foundation
import XCTest
@testable import QuotaWidgetApp

final class MenuProviderSelectionTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: - Normalisation

    func testMissingSettingFallsBackToTheQuotaProviders() {
        XCTAssertEqual(MenuProviderSelection.normalize(nil), [.claude, .codex, .kimi])
    }

    func testEmptyOrUnknownSettingFallsBack() {
        XCTAssertEqual(MenuProviderSelection.normalize([]), [.claude, .codex, .kimi])
        XCTAssertEqual(MenuProviderSelection.normalize(["nope", ""]), [.claude, .codex, .kimi])
    }

    func testOrderIsPreservedAndDuplicatesRemoved() {
        let normalized = MenuProviderSelection.normalize(
            ["openrouter", "kimi", "KIMI", "claude", "deepseek"]
        )

        XCTAssertEqual(normalized, [.openrouter, .kimi, .claude, .deepseek])
    }

    // MARK: - Config round trip

    func testConfigStoreRoundTripsTheSelection() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppConfigStore(baseDirectory: root)

        XCTAssertNil(store.readMenuProviders(), "nothing written yet")

        try store.writeMenuProviders(["kimi", "claude", "siliconflow"])
        XCTAssertEqual(store.readMenuProviders(), ["kimi", "claude", "siliconflow"])
    }

    func testWritingTheSelectionKeepsOtherSettings() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppConfigStore(baseDirectory: root)

        try store.writeCodexActiveRefresh(enabled: true, intervalSeconds: 900)
        try store.writeMenuProviders(["claude"])

        XCTAssertTrue(store.readCodexActiveRefresh(), "the Codex probe setting must survive")
        XCTAssertEqual(store.readMenuProviders(), ["claude"])
    }

    func testConfigStoreReadsTheLegacyTouchBarKey() throws {
        // A config written while the setting still drove the Touch Bar.
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppConfigStore(baseDirectory: root)
        try #"{"touchbar_providers":["openrouter","kimi"]}"#
            .write(to: store.configURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(store.readMenuProviders(), ["openrouter", "kimi"])

        // Writing migrates the key, so the old one cannot shadow later edits.
        try store.writeMenuProviders(["claude"])

        XCTAssertEqual(store.readMenuProviders(), ["claude"])
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: store.configURL)
        ) as? [String: Any]
        XCTAssertNil(json?["touchbar_providers"], "the legacy key is retired on write")
    }

    @MainActor
    func testRefreshIntervalIsSane() {
        XCTAssertGreaterThan(QuotaWidgetModel.refreshInterval, 0)
        XCTAssertLessThanOrEqual(QuotaWidgetModel.refreshInterval, 900)
    }

    // MARK: - View model

    @MainActor
    private func makeViewModel(root: URL) -> AccountSettingsViewModel {
        AccountSettingsViewModel(
            apiKeyStore: APIKeyStore(backend: InMemoryCredentialBackend()),
            siliconFlowConsoleStore: SiliconFlowConsoleSessionStore(backend: InMemoryCredentialBackend()),
            configStore: AppConfigStore(baseDirectory: root),
            usageStore: UsageStore(containerURLProvider: { nil }),
            autoload: false
        )
    }

    @MainActor
    func testViewModelDefaultsThenPersistsReordering() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = makeViewModel(root: root)

        viewModel.reload()
        XCTAssertEqual(viewModel.menuProviders, [.claude, .codex, .kimi])

        viewModel.moveMenuProvider(.kimi, by: -1)

        XCTAssertEqual(viewModel.menuProviders, [.claude, .kimi, .codex])
        XCTAssertEqual(
            AppConfigStore(baseDirectory: root).readMenuProviders(),
            ["claude", "kimi", "codex"],
            "reordering is written straight to the shared config"
        )
    }

    @MainActor
    func testViewModelAddsAndHidesProvidersAndKeepsOneVisible() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = makeViewModel(root: root)
        viewModel.reload()

        viewModel.setMenuProvider(.deepseek, enabled: true)
        XCTAssertTrue(viewModel.menuProviders.contains(.deepseek))
        XCTAssertFalse(viewModel.hiddenMenuProviders.contains(.deepseek))

        viewModel.setMenuProvider(.deepseek, enabled: false)
        XCTAssertFalse(viewModel.menuProviders.contains(.deepseek))
        XCTAssertTrue(viewModel.hiddenMenuProviders.contains(.deepseek))

        viewModel.setMenuProvider(.claude, enabled: false)
        viewModel.setMenuProvider(.codex, enabled: false)
        XCTAssertEqual(viewModel.menuProviders, [.kimi], "the last provider cannot be hidden")

        viewModel.setMenuProvider(.kimi, enabled: false)
        XCTAssertEqual(viewModel.menuProviders, [.kimi])
        XCTAssertEqual(viewModel.saveErrorText, "菜单至少保留一个 provider")
    }

    @MainActor
    func testViewModelCannotMovePastTheEnds() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = makeViewModel(root: root)
        viewModel.reload()

        viewModel.moveMenuProvider(.claude, by: -1)
        viewModel.moveMenuProvider(.kimi, by: 1)

        XCTAssertEqual(viewModel.menuProviders, [.claude, .codex, .kimi])
    }
}
