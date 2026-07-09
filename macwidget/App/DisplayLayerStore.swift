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

struct DisplayLayerStore: Sendable {
    let homeDirectory: URL
    let applicationsDirectory: URL
    let resourceDirectory: URL
    let installStateDirectory: URL?
    let processList: @Sendable () -> [String]
    let openURL: @Sendable (URL) -> Bool
    let runCommand: @Sendable (DisplayLayerCommand) throws -> Void

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        resourceDirectory: URL = Bundle.main.resourceURL ?? Bundle.main.bundleURL,
        installStateDirectory: URL? = nil,
        processList: @escaping @Sendable () -> [String] = DisplayLayerStore.defaultProcessList,
        openURL: @escaping @Sendable (URL) -> Bool = { NSWorkspace.shared.open($0) },
        runCommand: @escaping @Sendable (DisplayLayerCommand) throws -> Void = DisplayLayerStore.defaultRunCommand
    ) {
        self.homeDirectory = homeDirectory
        self.applicationsDirectory = applicationsDirectory
        self.resourceDirectory = resourceDirectory
        self.installStateDirectory = installStateDirectory
        self.processList = processList
        self.openURL = openURL
        self.runCommand = runCommand
    }

    static func defaultInstallStateDirectory() -> URL {
        AppConfigStore.defaultDirectory()
            .appendingPathComponent("display-layers", isDirectory: true)
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
            let installed = installStateDirectory == nil
                ? Self.ubersichtWidgetDirectories(homeDirectory: homeDirectory).contains { base in
                    FileManager.default.fileExists(atPath: base.appendingPathComponent("usage-widget/index.jsx").path)
                }
                : isRecordedInstalled(.ubersicht)
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
        let destinations = Self.ubersichtWidgetDirectories(homeDirectory: homeDirectory)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let targets = destinations.isEmpty
            ? [Self.ubersichtWidgetDirectories(homeDirectory: homeDirectory)[0]]
            : destinations

        for base in targets {
            let destination = base.appendingPathComponent("usage-widget", isDirectory: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceDirectory, to: destination)
        }
        try recordInstalled(.ubersicht)
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
        try recordInstalled(.touchBar)
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
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.components(separatedBy: .newlines) ?? []
        } catch {
            return []
        }
    }

    private func isRecordedInstalled(_ layer: DisplayLayer) -> Bool {
        guard let installStateDirectory else { return false }
        return FileManager.default.fileExists(atPath: markerURL(for: layer, in: installStateDirectory).path)
    }

    private func recordInstalled(_ layer: DisplayLayer) throws {
        guard let installStateDirectory else { return }
        try FileManager.default.createDirectory(at: installStateDirectory, withIntermediateDirectories: true)
        try Data().write(to: markerURL(for: layer, in: installStateDirectory), options: [.atomic])
    }

    private func markerURL(for layer: DisplayLayer, in directory: URL) -> URL {
        directory.appendingPathComponent("\(layer.rawValue).installed")
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
