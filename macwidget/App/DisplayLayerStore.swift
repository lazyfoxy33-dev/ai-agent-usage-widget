import AppKit
import Foundation

enum DisplayLayer: String, CaseIterable, Identifiable {
    case ubersicht
    case widgetKit
    case touchBar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ubersicht: return "Übersicht"
        case .widgetKit: return "macOS Widget"
        case .touchBar: return "Touch Bar / Bar"
        }
    }
}

struct DisplayLayerStatus: Equatable, Identifiable {
    var id: DisplayLayer { layer }
    let layer: DisplayLayer
    let installed: Bool
    let running: Bool
    let detail: String
}

struct DisplayLayerCommand: Equatable {
    let executable: URL
    let arguments: [String]
    let workingDirectory: URL
    let environment: [String: String]
}

enum DisplayLayerStoreError: Error, LocalizedError {
    case missingBundledUbersichtWidget(URL)
    case missingBundledTouchBarInstaller(URL)
    case openFailed(URL)

    var errorDescription: String? {
        switch self {
        case .missingBundledUbersichtWidget(let url):
            return "Bundled Übersicht widget is missing at \(url.path)"
        case .missingBundledTouchBarInstaller(let url):
            return "Bundled Touch Bar installer is missing at \(url.path)"
        case .openFailed(let url):
            return "Could not open \(url.path)"
        }
    }
}

struct DisplayLayerStore {
    let homeDirectory: URL
    let applicationsDirectory: URL
    let resourceDirectory: URL
    let processList: () -> [String]
    let openURL: (URL) -> Bool
    let runCommand: (DisplayLayerCommand) throws -> Void

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        resourceDirectory: URL = Bundle.main.resourceURL ?? Bundle.main.bundleURL,
        processList: @escaping () -> [String] = DisplayLayerStore.defaultProcessList,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        runCommand: @escaping (DisplayLayerCommand) throws -> Void = DisplayLayerStore.defaultRunCommand
    ) {
        self.homeDirectory = homeDirectory
        self.applicationsDirectory = applicationsDirectory
        self.resourceDirectory = resourceDirectory
        self.processList = processList
        self.openURL = openURL
        self.runCommand = runCommand
    }

    static func ubersichtWidgetDirectories(homeDirectory: URL) -> [URL] {
        [
            homeDirectory.appendingPathComponent("Library/Application Support/Übersicht/widgets", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Application Support/Übersicht/widgets", isDirectory: true)
        ]
    }

    func status(for layer: DisplayLayer) -> DisplayLayerStatus {
        switch layer {
        case .ubersicht:
            let installed = Self.ubersichtWidgetDirectories(homeDirectory: homeDirectory).contains { base in
                FileManager.default.fileExists(atPath: base.appendingPathComponent("usage-widget/index.jsx").path)
            }
            let running = processList().contains { $0.localizedCaseInsensitiveContains("Übersicht") || $0.localizedCaseInsensitiveContains("Übersicht") }
            return DisplayLayerStatus(layer: layer, installed: installed, running: running, detail: installed ? "Installed" : "Not installed")
        case .widgetKit:
            return DisplayLayerStatus(layer: layer, installed: true, running: false, detail: "Bundled with QuotaWidget.app")
        case .touchBar:
            let installed = FileManager.default.fileExists(atPath: applicationsDirectory.appendingPathComponent("QuotaBar.app").path)
            let running = processList().contains { $0.localizedCaseInsensitiveContains("QuotaBar") }
            return DisplayLayerStatus(layer: layer, installed: installed, running: running, detail: installed ? "Installed" : "Not installed")
        }
    }

    func installUbersichtWidget(from sourceDirectory: URL) throws {
        let candidates = Self.ubersichtWidgetDirectories(homeDirectory: homeDirectory)
        let targetBase = candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]

        for base in candidates {
            let destination = base.appendingPathComponent("usage-widget", isDirectory: true)
            guard FileManager.default.fileExists(atPath: destination.path) else { continue }
            try FileManager.default.removeItem(at: destination)
        }

        let destination = targetBase.appendingPathComponent("usage-widget", isDirectory: true)
        try FileManager.default.createDirectory(at: targetBase, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceDirectory, to: destination)
        try removePackagedUbersichtArtifacts(from: destination)
    }

    func installBundledUbersichtWidget() throws {
        let source = resourceDirectory
            .appendingPathComponent("display-layers/usage-widget", isDirectory: true)
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent("index.jsx").path) else {
            throw DisplayLayerStoreError.missingBundledUbersichtWidget(source)
        }
        try installUbersichtWidget(from: source)
        try installBundledCoreIntoUbersichtWidgets()
    }

    private func installBundledCoreIntoUbersichtWidgets() throws {
        let core = resourceDirectory.appendingPathComponent("core", isDirectory: true)
        let fetcher = core.appendingPathComponent("fetch_usage.py")
        let usagePackage = core.appendingPathComponent("usage", isDirectory: true)
        guard FileManager.default.fileExists(atPath: fetcher.path) else { return }

        for base in Self.ubersichtWidgetDirectories(homeDirectory: homeDirectory) {
            let destination = base.appendingPathComponent("usage-widget", isDirectory: true)
            guard FileManager.default.fileExists(atPath: destination.path) else { continue }
            let destinationFetcher = destination.appendingPathComponent("fetch_usage.py")
            if FileManager.default.fileExists(atPath: destinationFetcher.path) {
                try FileManager.default.removeItem(at: destinationFetcher)
            }
            try FileManager.default.copyItem(at: fetcher, to: destinationFetcher)

            let destinationUsage = destination.appendingPathComponent("usage", isDirectory: true)
            if FileManager.default.fileExists(atPath: destinationUsage.path) {
                try FileManager.default.removeItem(at: destinationUsage)
            }
            if FileManager.default.fileExists(atPath: usagePackage.path) {
                try FileManager.default.copyItem(at: usagePackage, to: destinationUsage)
            }
        }
    }

    private func removePackagedUbersichtArtifacts(from destination: URL) throws {
        let nestedWidgetBuild = destination.appendingPathComponent("dist", isDirectory: true)
        if FileManager.default.fileExists(atPath: nestedWidgetBuild.path) {
            try FileManager.default.removeItem(at: nestedWidgetBuild)
        }
    }

    func openUbersichtWidgetsDirectory() throws {
        let candidates = Self.ubersichtWidgetDirectories(homeDirectory: homeDirectory)
        let destination = candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        guard openURL(destination) else { throw DisplayLayerStoreError.openFailed(destination) }
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
                "QUOTABAR_INSTALL_DESTINATION": applicationsDirectory
                    .appendingPathComponent("QuotaBar.app")
                    .path
            ]
        )
    }

    func installTouchBar() throws {
        try runCommand(touchBarInstallCommand())
    }

    func openTouchBarApp() throws {
        let app = applicationsDirectory.appendingPathComponent("QuotaBar.app")
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw DisplayLayerStoreError.openFailed(app)
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
