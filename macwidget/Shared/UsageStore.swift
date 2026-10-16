import Foundation

struct UsageStoreStatus: Equatable {
    enum Reason: Equatable {
        case ok
        case missingContainer
        case missingUsageFile
    }

    let available: Bool
    let reason: Reason
    let usagePath: String?
    let modifiedAt: Date?
}

struct UsageStore: Sendable {
    private let containerURLProvider: @Sendable () -> URL?

    init(containerURLProvider: @escaping @Sendable () -> URL? = UsageStore.defaultContainerURL) {
        self.containerURLProvider = containerURLProvider
    }

    func status() -> UsageStoreStatus {
        guard let container = containerURLProvider() else {
            return UsageStoreStatus(
                available: false,
                reason: .missingContainer,
                usagePath: nil,
                modifiedAt: nil
            )
        }

        let url = container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("usage.json")

        guard FileManager.default.fileExists(atPath: url.path) else {
            return UsageStoreStatus(
                available: false,
                reason: .missingUsageFile,
                usagePath: url.path,
                modifiedAt: nil
            )
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return UsageStoreStatus(
            available: true,
            reason: .ok,
            usagePath: url.path,
            modifiedAt: attrs?[.modificationDate] as? Date
        )
    }

    func read() throws -> String {
        try String(contentsOf: fileURL, encoding: .utf8)
    }

    func write(_ json: String) throws {
        let target = try fileURL
        let directory = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let temporary = directory.appendingPathComponent(
            ".usage-\(UUID().uuidString).tmp"
        )
        try json.write(to: temporary, atomically: false, encoding: .utf8)
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: target)
        }
    }

    private var fileURL: URL {
        get throws {
            guard let container = containerURLProvider() else {
                throw CocoaError(.fileNoSuchFile)
            }
            return container
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent("usage.json")
        }
    }

    private static func defaultContainerURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["QUOTAWIDGET_SHARED_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        guard let identifier = Bundle.main.object(
            forInfoDictionaryKey: "AppGroupIdentifier"
        ) as? String else {
            return nil
        }
        return FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        )
    }
}
