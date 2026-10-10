import Foundation
import XCTest
@testable import QuotaWidgetApp

final class TouchBarSelectionTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: - Normalisation

    func testMissingSettingFallsBackToTheQuotaProviders() {
        XCTAssertEqual(TouchBarSelection.normalize(nil), [.claude, .codex, .kimi])
    }

    func testEmptyOrUnknownSettingFallsBack() {
        XCTAssertEqual(TouchBarSelection.normalize([]), [.claude, .codex, .kimi])
        XCTAssertEqual(TouchBarSelection.normalize(["nope", ""]), [.claude, .codex, .kimi])
    }

    func testOrderIsPreservedAndDuplicatesRemoved() {
        let normalized = TouchBarSelection.normalize(["openrouter", "kimi", "KIMI", "claude", "deepseek"])

        XCTAssertEqual(normalized, [.openrouter, .kimi, .claude, .deepseek])
    }

    // MARK: - Config round trip

    func testConfigStoreRoundTripsTheTouchBarSelection() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppConfigStore(baseDirectory: root)

        XCTAssertNil(store.readTouchBarProviders(), "nothing written yet")

        try store.writeTouchBarProviders(["kimi", "claude", "siliconflow"])
        XCTAssertEqual(store.readTouchBarProviders(), ["kimi", "claude", "siliconflow"])
    }

    func testWritingTheSelectionKeepsOtherSettings() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppConfigStore(baseDirectory: root)

        try store.writeCodexActiveRefresh(enabled: true, intervalSeconds: 900)
        try store.writeTouchBarProviders(["claude"])

        XCTAssertTrue(store.readCodexActiveRefresh(), "the Codex probe setting must survive")
        XCTAssertEqual(store.readTouchBarProviders(), ["claude"])
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
        XCTAssertEqual(viewModel.touchBarProviders, [.claude, .codex, .kimi])

        viewModel.moveTouchBarProvider(.kimi, by: -1)

        XCTAssertEqual(viewModel.touchBarProviders, [.claude, .kimi, .codex])
        XCTAssertEqual(
            AppConfigStore(baseDirectory: root).readTouchBarProviders(),
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

        viewModel.setTouchBarProvider(.deepseek, enabled: true)
        XCTAssertTrue(viewModel.touchBarProviders.contains(.deepseek))
        XCTAssertFalse(viewModel.hiddenTouchBarProviders.contains(.deepseek))

        viewModel.setTouchBarProvider(.deepseek, enabled: false)
        XCTAssertFalse(viewModel.touchBarProviders.contains(.deepseek))
        XCTAssertTrue(viewModel.hiddenTouchBarProviders.contains(.deepseek))

        viewModel.setTouchBarProvider(.claude, enabled: false)
        viewModel.setTouchBarProvider(.codex, enabled: false)
        XCTAssertEqual(viewModel.touchBarProviders, [.kimi], "the last provider cannot be hidden")

        viewModel.setTouchBarProvider(.kimi, enabled: false)
        XCTAssertEqual(viewModel.touchBarProviders, [.kimi])
        XCTAssertEqual(viewModel.saveErrorText, "Touch Bar 至少保留一个 provider")
    }

    @MainActor
    func testViewModelCannotMovePastTheEnds() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = makeViewModel(root: root)
        viewModel.reload()

        viewModel.moveTouchBarProvider(.claude, by: -1)
        viewModel.moveTouchBarProvider(.kimi, by: 1)

        XCTAssertEqual(viewModel.touchBarProviders, [.claude, .codex, .kimi])
    }
}
