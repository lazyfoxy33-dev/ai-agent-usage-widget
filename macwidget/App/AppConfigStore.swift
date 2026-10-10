import Foundation

struct AppConfigStore {
    private let baseDirectory: URL

    init(baseDirectory: URL = AppConfigStore.defaultDirectory()) {
        self.baseDirectory = baseDirectory
    }

    var configURL: URL {
        baseDirectory.appendingPathComponent("config.json")
    }

    func writeCodexActiveRefresh(enabled: Bool, intervalSeconds: Int = 1800) throws {
        var payload: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = existing
        }
        payload["codex_active_refresh"] = enabled
        payload["codex_refresh_interval_seconds"] = intervalSeconds
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: configURL, options: [.atomic])
    }

    /// Provider raw values shown on the Touch Bar, in display order.
    /// `nil` when the setting was never written (callers apply their own default).
    func readTouchBarProviders() -> [String]? {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = json["touchbar_providers"] as? [String]
        else {
            return nil
        }
        return providers
    }

    func writeTouchBarProviders(_ providers: [String]) throws {
        var payload: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = existing
        }
        payload["touchbar_providers"] = providers
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: configURL, options: [.atomic])
    }

    func readCodexActiveRefresh() -> Bool {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return json["codex_active_refresh"] as? Bool == true
    }

    static func defaultDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["AI_AGENT_USAGE_CONFIG"] {
            return URL(fileURLWithPath: override).deletingLastPathComponent()
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ai-agent-usage-widget", isDirectory: true)
    }
}
