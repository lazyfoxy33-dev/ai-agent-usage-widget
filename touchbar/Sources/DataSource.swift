import Foundation

// The Touch Bar app shares ONE data layer with the Übersicht widget: the Python
// package under `core/` (fetch_usage.py + usage/). We never re-implement provider
// fetching in Swift — we run the exact same script and read its JSON. Credentials
// stay read-only and there is no token refresh, matching the project's policy.
//
// `core/` is copied into the app bundle at build time (Contents/Resources/core).

// MARK: - Model

/// One quota window. `usedPct` is percent *used* (0...100), matching the widget.
struct Window {
    var usedPct: Double
    var resetsAt: Date?
    var stale: Bool          // window already reset; figure is outdated (Codex)
}

/// One provider's snapshot, mirroring fetch_usage.py's JSON.
struct Provider {
    var ok: Bool
    var reason: String?      // "expired" | "error" | "no_data" | "stale" | nil
    var fiveH: Window?
    var weekly: Window?
    var asOf: Date?          // Codex: timestamp of the latest event used
}

struct Usage {
    var claude = Provider(ok: false, reason: "loading")
    var codex  = Provider(ok: false, reason: "loading")
    var kimi   = Provider(ok: false, reason: "loading")
    var updatedAt = Date()
}

// MARK: - Source

enum UsageSource {
    /// Path to the bundled (or dev) fetch_usage.py.
    static func scriptPath() -> String? {
        if let override = ProcessInfo.processInfo.environment["QUOTABAR_FETCH"] {
            return override
        }
        // Inside the app bundle: Contents/Resources/core/fetch_usage.py
        if let res = Bundle.main.resourcePath {
            let p = res + "/core/fetch_usage.py"
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        // Dev fallback: ../core relative to the source tree.
        let dev = FileManager.default.currentDirectoryPath + "/../core/fetch_usage.py"
        if FileManager.default.fileExists(atPath: dev) { return dev }
        return nil
    }

    /// Runs the shared fetcher and parses its JSON. Off the main thread.
    static func read() -> Usage {
        var usage = Usage()
        guard let script = scriptPath() else {
            let p = Provider(ok: false, reason: "no fetcher")
            usage.claude = p; usage.codex = p; usage.kimi = p
            return usage
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [script]
        // Python puts the script's own dir on sys.path[0], so `import usage` works.
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            let p = Provider(ok: false, reason: "fetch failed")
            usage.claude = p; usage.codex = p; usage.kimi = p
            return usage
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            let p = Provider(ok: false, reason: "bad output")
            usage.claude = p; usage.codex = p; usage.kimi = p
            return usage
        }
        usage.claude = provider(from: root["claude"])
        usage.codex  = provider(from: root["codex"])
        usage.kimi   = provider(from: root["kimi"])
        usage.updatedAt = Date()
        return usage
    }

    private static func provider(from any: Any?) -> Provider {
        guard let o = any as? [String: Any] else { return Provider(ok: false, reason: "missing") }
        var p = Provider(ok: (o["ok"] as? Bool) ?? false)
        p.reason = o["reason"] as? String
        p.fiveH  = window(from: o["five_h"])
        p.weekly = window(from: o["weekly"])
        if let a = o["as_of"] as? Double { p.asOf = Date(timeIntervalSince1970: a) }
        return p
    }

    private static func window(from any: Any?) -> Window? {
        guard let o = any as? [String: Any], let pct = o["pct"] as? Double else { return nil }
        var reset: Date?
        if let r = o["resets_at"] as? Double { reset = Date(timeIntervalSince1970: r) }
        return Window(usedPct: pct, resetsAt: reset, stale: (o["stale"] as? Bool) ?? false)
    }
}
