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
struct DisplayLayerStore: Sendable {
    static let touchBarAppName = "QuotaBar.app"

    let applicationsDirectory: URL
    let resourceDirectory: URL
    let processList: @Sendable () -> [String]
    let openURL: @Sendable (URL) -> Bool
    let runCommand: @Sendable (DisplayLayerCommand) throws -> Void

    init(
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        resourceDirectory: URL = Bundle.main.resourceURL ?? Bundle.main.bundleURL,
        processList: @escaping @Sendable () -> [String] = DisplayLayerStore.defaultProcessList,
        openURL: @escaping @Sendable (URL) -> Bool = { NSWorkspace.shared.open($0) },
        runCommand: @escaping @Sendable (DisplayLayerCommand) throws -> Void = DisplayLayerStore.defaultRunCommand
    ) {
        self.applicationsDirectory = applicationsDirectory
        self.resourceDirectory = resourceDirectory
        self.processList = processList
        self.openURL = openURL
        self.runCommand = runCommand
    }

    var touchBarAppURL: URL {
        applicationsDirectory.appendingPathComponent(Self.touchBarAppName)
    }

    func touchBarStatus() -> DisplayLayerStatus {
        let installed = FileManager.default.fileExists(atPath: touchBarAppURL.path)
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
                "QUOTABAR_INSTALL_DESTINATION": touchBarAppURL.path
            ]
        )
    }

    func installTouchBar() throws {
        try runCommand(touchBarInstallCommand())
    }

    func openTouchBarApp() throws {
        guard FileManager.default.fileExists(atPath: touchBarAppURL.path) else {
            throw DisplayLayerStoreError.openFailed(touchBarAppURL)
        }
        guard openURL(touchBarAppURL) else { throw DisplayLayerStoreError.openFailed(touchBarAppURL) }
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
