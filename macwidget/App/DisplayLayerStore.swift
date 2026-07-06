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

struct DisplayLayerStore {
    let homeDirectory: URL
    let applicationsDirectory: URL
    let processList: () -> [String]

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        processList: @escaping () -> [String] = DisplayLayerStore.defaultProcessList
    ) {
        self.homeDirectory = homeDirectory
        self.applicationsDirectory = applicationsDirectory
        self.processList = processList
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
}
