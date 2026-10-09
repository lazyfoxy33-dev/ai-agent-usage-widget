import Foundation
import XCTest
@testable import QuotaWidgetApp

final class DisplayLayerStoreTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testTouchBarStatusReportsMissingApp() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DisplayLayerStore(
            applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true),
            resourceDirectory: root,
            processList: { [] }
        )

        let status = store.touchBarStatus()

        XCTAssertFalse(status.installed)
        XCTAssertFalse(status.running)
        XCTAssertEqual(status.detail, "Not installed")
    }

    func testTouchBarStatusDetectsInstalledApp() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let app = applications.appendingPathComponent("QuotaBar.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

        let store = DisplayLayerStore(
            applicationsDirectory: applications,
            resourceDirectory: root,
            processList: { [] }
        )

        let status = store.touchBarStatus()

        XCTAssertTrue(status.installed)
        XCTAssertFalse(status.running)
        XCTAssertEqual(status.detail, "Installed")
    }

    func testTouchBarStatusReportsRunningProcess() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(
            at: applications.appendingPathComponent("QuotaBar.app", isDirectory: true),
            withIntermediateDirectories: true
        )

        let store = DisplayLayerStore(
            applicationsDirectory: applications,
            resourceDirectory: root,
            processList: { ["/bin/launchd", "/Applications/QuotaBar.app/Contents/MacOS/QuotaBar"] }
        )

        let status = store.touchBarStatus()

        XCTAssertTrue(status.installed)
        XCTAssertTrue(status.running)
        XCTAssertEqual(status.detail, "Installed, running")
    }

    func testTouchBarInstallCommandUsesBundledInstallerAndConfigurableDestination() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let resources = root.appendingPathComponent("resources", isDirectory: true)
        let installer = resources.appendingPathComponent("display-layers/touchbar/install.sh")
        try FileManager.default.createDirectory(
            at: installer.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/bash".write(to: installer, atomically: true, encoding: .utf8)

        let store = DisplayLayerStore(
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
    }

    func testTouchBarInstallCommandThrowsWhenInstallerIsMissing() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DisplayLayerStore(
            applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true),
            resourceDirectory: root,
            processList: { [] }
        )

        XCTAssertThrowsError(try store.touchBarInstallCommand()) { error in
            guard case DisplayLayerStoreError.missingBundledTouchBarInstaller = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testInstallTouchBarRunsInstallerCommand() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let resources = root.appendingPathComponent("resources", isDirectory: true)
        let installer = resources.appendingPathComponent("display-layers/touchbar/install.sh")
        try FileManager.default.createDirectory(
            at: installer.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/bash".write(to: installer, atomically: true, encoding: .utf8)

        final class Recorder: @unchecked Sendable {
            var commands: [DisplayLayerCommand] = []
        }
        let recorder = Recorder()

        let store = DisplayLayerStore(
            applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true),
            resourceDirectory: resources,
            processList: { [] },
            runCommand: { recorder.commands.append($0) }
        )

        try store.installTouchBar()

        XCTAssertEqual(recorder.commands.count, 1)
        XCTAssertEqual(recorder.commands.first?.workingDirectory, installer.deletingLastPathComponent())
    }

    func testOpenTouchBarAppThrowsWhenAppIsMissing() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DisplayLayerStore(
            applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true),
            resourceDirectory: root,
            processList: { [] },
            openURL: { _ in XCTFail("openURL must not be called"); return false }
        )

        XCTAssertThrowsError(try store.openTouchBarApp()) { error in
            guard case DisplayLayerStoreError.openFailed = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testOpenTouchBarAppOpensInstalledApp() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let app = applications.appendingPathComponent("QuotaBar.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

        final class Opened: @unchecked Sendable {
            var urls: [URL] = []
        }
        let opened = Opened()

        let store = DisplayLayerStore(
            applicationsDirectory: applications,
            resourceDirectory: root,
            processList: { [] },
            openURL: { url in
                opened.urls.append(url)
                return true
            }
        )

        try store.openTouchBarApp()

        XCTAssertEqual(opened.urls, [app])
    }
}
