import Foundation
import XCTest
@testable import QuotaWidgetApp

final class DisplayLayerStoreTests: XCTestCase {
    func testUbersichtDestinationCandidatesIncludeBothUnicodeForms() {
        let home = URL(fileURLWithPath: "/tmp/home", isDirectory: true)
        let candidates = DisplayLayerStore.ubersichtWidgetDirectories(homeDirectory: home)
            .map(\.path)

        XCTAssertTrue(candidates.contains("/tmp/home/Library/Application Support/Übersicht/widgets"))
        XCTAssertTrue(candidates.contains("/tmp/home/Library/Application Support/Übersicht/widgets"))
    }

    func testDisplayStatusDetectsInstalledUbersichtWidget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let widget = root
            .appendingPathComponent("Library/Application Support/Übersicht/widgets/usage-widget", isDirectory: true)
        try FileManager.default.createDirectory(at: widget, withIntermediateDirectories: true)
        try "marker".write(to: widget.appendingPathComponent("index.jsx"), atomically: true, encoding: .utf8)

        let store = DisplayLayerStore(
            homeDirectory: root,
            applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true),
            processList: { [] }
        )

        let status = store.status(for: .ubersicht)

        XCTAssertEqual(status.layer, .ubersicht)
        XCTAssertTrue(status.installed)
        XCTAssertFalse(status.running)

        try? FileManager.default.removeItem(at: root)
    }

    func testDisplayStatusUsesRecordedUbersichtInstallStateWhenConfigured() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try Data().write(to: state.appendingPathComponent("ubersicht.installed"))

        let store = DisplayLayerStore(
            homeDirectory: root.appendingPathComponent("home", isDirectory: true),
            applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true),
            installStateDirectory: state,
            processList: { [] }
        )

        let status = store.status(for: .ubersicht)

        XCTAssertTrue(status.installed)
        XCTAssertEqual(status.detail, "Installed")

        try? FileManager.default.removeItem(at: root)
    }

    func testInstallUbersichtCopiesWidgetIntoExistingDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let widgets = root.appendingPathComponent("Library/Application Support/Übersicht/widgets", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: widgets, withIntermediateDirectories: true)
        try "widget".write(to: source.appendingPathComponent("index.jsx"), atomically: true, encoding: .utf8)

        let store = DisplayLayerStore(
            homeDirectory: root,
            applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true),
            processList: { [] }
        )

        try store.installUbersichtWidget(from: source)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: widgets.appendingPathComponent("usage-widget/index.jsx").path
        ))

        try? FileManager.default.removeItem(at: root)
    }

    func testInstallUbersichtRecordsInstallStateWhenConfigured() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "widget".write(to: source.appendingPathComponent("index.jsx"), atomically: true, encoding: .utf8)

        let store = DisplayLayerStore(
            homeDirectory: root,
            applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true),
            installStateDirectory: state,
            processList: { [] }
        )

        try store.installUbersichtWidget(from: source)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: state.appendingPathComponent("ubersicht.installed").path
        ))

        try? FileManager.default.removeItem(at: root)
    }

    func testWidgetKitStatusIsBundledAndReportsSharedStateDetail() {
        let store = DisplayLayerStore(
            homeDirectory: URL(fileURLWithPath: "/tmp/home", isDirectory: true),
            applicationsDirectory: URL(fileURLWithPath: "/tmp/apps", isDirectory: true),
            processList: { [] }
        )

        let status = store.status(for: .widgetKit)

        XCTAssertEqual(status.layer, .widgetKit)
        XCTAssertTrue(status.installed)
        XCTAssertTrue(status.detail.contains("Bundled"))
    }

    func testBundledUbersichtInstallUsesDisplayLayerResources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resources = root.appendingPathComponent("resources", isDirectory: true)
        let source = resources
            .appendingPathComponent("display-layers/usage-widget", isDirectory: true)
        let core = resources
            .appendingPathComponent("core/usage", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: core, withIntermediateDirectories: true)
        try "widget".write(to: source.appendingPathComponent("index.jsx"), atomically: true, encoding: .utf8)
        try "fetch".write(to: resources.appendingPathComponent("core/fetch_usage.py"), atomically: true, encoding: .utf8)
        try "module".write(to: core.appendingPathComponent("__init__.py"), atomically: true, encoding: .utf8)

        let store = DisplayLayerStore(
            homeDirectory: root,
            applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true),
            resourceDirectory: resources,
            processList: { [] }
        )

        try store.installBundledUbersichtWidget()

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root
                .appendingPathComponent("Library/Application Support/Übersicht/widgets/usage-widget/index.jsx")
                .path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root
                .appendingPathComponent("Library/Application Support/Übersicht/widgets/usage-widget/fetch_usage.py")
                .path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root
                .appendingPathComponent("Library/Application Support/Übersicht/widgets/usage-widget/usage/__init__.py")
                .path
        ))

        try? FileManager.default.removeItem(at: root)
    }

    func testTouchBarInstallCommandUsesBundledInstallerAndConfigurableDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resources = root.appendingPathComponent("resources", isDirectory: true)
        let installer = resources
            .appendingPathComponent("display-layers/touchbar/install.sh")
        try FileManager.default.createDirectory(at: installer.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/bash".write(to: installer, atomically: true, encoding: .utf8)

        let store = DisplayLayerStore(
            homeDirectory: root,
            applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true),
            resourceDirectory: resources,
            processList: { [] }
        )

        let command = try store.touchBarInstallCommand()

        XCTAssertEqual(command.executable.path, "/bin/bash")
        XCTAssertEqual(command.arguments, ["install.sh"])
        XCTAssertEqual(command.workingDirectory, installer.deletingLastPathComponent())
        XCTAssertEqual(
            command.environment["QUOTABAR_INSTALL_DESTINATION"],
            root.appendingPathComponent("Applications/QuotaBar.app").path
        )

        try? FileManager.default.removeItem(at: root)
    }
}
