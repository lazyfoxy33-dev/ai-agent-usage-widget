import AppKit
import Foundation

struct DisplayLayerStatus: Equatable {
    let installed: Bool
    let running: Bool
    let detail: String

    static let checking = DisplayLayerStatus(installed: false, running: false, detail: "Checking...")
}

struct DisplayLayerCommand: Equatable {
    let executable: URL
    let arguments: [String]
    let workingDirectory: URL
    let environment: [String: String]
}

enum DisplayLayerStoreError: Error, LocalizedError {
    case missingBundledTouchBarInstaller(URL)
    case openFailed(URL)

    var errorDescription: String? {
        switch self {
        case .missingBundledTouchBarInstaller(let url):
            return "Bundled Touch Bar installer is missing at \(url.path)"
        case .openFailed(let url):
            return "Could not open \(url.path)"
        }
    }
}

/// Installs and opens the bundled Touch Bar frontend (`QuotaBar.app`).
///
/// `touchbar/install.sh` writes to `~/Applications`, while this app installs to
/// `/Applications`, so both locations count as "installed".
struct DisplayLayerStore: Sendable {
    static let touchBarAppName = "QuotaBar.app"

    let applicationsDirectory: URL
    let userApplicationsDirectory: URL
    let resourceDirectory: URL
    let processList: @Sendable () -> [String]
    let openURL: @Sendable (URL) -> Bool
    let runCommand: @Sendable (DisplayLayerCommand) throws -> Void

    init(
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        userApplicationsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true),
        resourceDirectory: URL = Bundle.main.resourceURL ?? Bundle.main.bundleURL,
        processList: @escaping @Sendable () -> [String] = DisplayLayerStore.defaultProcessList,
        openURL: @escaping @Sendable (URL) -> Bool = { NSWorkspace.shared.open($0) },
        runCommand: @escaping @Sendable (DisplayLayerCommand) throws -> Void = DisplayLayerStore.defaultRunCommand
    ) {
        self.applicationsDirectory = applicationsDirectory
        self.userApplicationsDirectory = userApplicationsDirectory
        self.resourceDirectory = resourceDirectory
        self.processList = processList
        self.openURL = openURL
        self.runCommand = runCommand
    }

    /// Accepted install locations, in preference order.
    var touchBarAppURLs: [URL] {
        [
            applicationsDirectory.appendingPathComponent(Self.touchBarAppName),
            userApplicationsDirectory.appendingPathComponent(Self.touchBarAppName)
        ]
    }

    /// Where `Install / Update` writes.
    var touchBarInstallDestination: URL { touchBarAppURLs[0] }

    /// The first accepted location that actually exists.
    var installedTouchBarAppURL: URL? {
        touchBarAppURLs.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func touchBarStatus() -> DisplayLayerStatus {
        let installed = installedTouchBarAppURL != nil
        let running = processList().contains { $0.localizedCaseInsensitiveContains("QuotaBar") }
        let detail: String
        if !installed {
            detail = "Not installed"
        } else {
            detail = running ? "Installed, running" : "Installed"
        }
        return DisplayLayerStatus(installed: installed, running: running, detail: detail)
    }

    func touchBarInstallCommand() throws -> DisplayLayerCommand {
        let installer = resourceDirectory
            .appendingPathComponent("display-layers/touchbar/install.sh")
        guard FileManager.default.fileExists(atPath: installer.path) else {
            throw DisplayLayerStoreError.missingBundledTouchBarInstaller(installer)
        }
        return DisplayLayerCommand(
            executable: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["install.sh"],
            workingDirectory: installer.deletingLastPathComponent(),
            environment: [
                "QUOTABAR_INSTALL_DESTINATION": touchBarInstallDestination.path
            ]
        )
    }

    func installTouchBar() throws {
        try runCommand(touchBarInstallCommand())
    }

    func openTouchBarApp() throws {
        guard let app = installedTouchBarAppURL else {
            throw DisplayLayerStoreError.openFailed(touchBarInstallDestination)
        }
        guard openURL(app) else { throw DisplayLayerStoreError.openFailed(app) }
    }

    private static func defaultProcessList() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(data: data, encoding: .utf8)?.components(separatedBy: .newlines) ?? []
        } catch {
            return []
        }
    }

    private static func defaultRunCommand(_ command: DisplayLayerCommand) throws {
        let task = Process()
        task.executableURL = command.executable
        task.arguments = command.arguments
        task.currentDirectoryURL = command.workingDirectory
        task.environment = ProcessInfo.processInfo.environment.merging(command.environment) { _, new in new }
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            throw CocoaError(.executableLoad)
        }
    }
}
