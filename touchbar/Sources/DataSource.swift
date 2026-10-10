import Foundation

// The Touch Bar app shares ONE data layer with the menu bar app: the Python
// package under `core/` (fetch_usage.py + usage/). We never re-implement provider
// fetching in Swift — we run the exact same script and read its JSON. Credential
// lifecycle policy remains centralized in the shared Python layer.
//
// `core/` is copied into the app bundle at build time (Contents/Resources/core).

// MARK: - Model

/// One quota window. `usedPct` is percent *used* (0...100), matching the widget.
struct Window {
    var usedPct: Double
    var resetsAt: Date?
    var stale: Bool          // window already reset; figure is outdated (Codex)
}

/// One balance-provider account snapshot.
struct Balance {
    var amount: Double
    var currency: String
    var available: Bool
    var label: String
}

/// Recent-spend estimate for balance providers.
struct BurnRate {
    var amountPerDay: Double?
    var windowDays: Int?
    var estimatedDaysLeft: Int?
    var confidence: String
    var reason: String?
}

/// One provider's snapshot, mirroring fetch_usage.py's JSON.
struct Provider {
    var ok: Bool
    var reason: String?      // "expired" | "error" | "no_data" | "stale" | "rate_limited" | nil
    var kind: String?
    /// Where the figures came from, e.g. "console_session" or "dsh".
    var source: String?
    var fiveH: Window?
    var weekly: Window?
    var balance: Balance?
    var burnRate: BurnRate?
    var asOf: Date?          // Codex: timestamp of the latest event used
    var live: Bool?          // nil keeps compatibility with older payloads
    var fetchedAt: Date?
}

struct Usage {
    var claude = Provider(ok: false, reason: "loading")
    var codex  = Provider(ok: false, reason: "loading")
    var kimi   = Provider(ok: false, reason: "loading")
    var deepseek = Provider(ok: false, reason: "loading")
    var siliconflow = Provider(ok: false, reason: "loading")
    var openrouter = Provider(ok: false, reason: "loading")
    var updatedAt = Date()
    /// Where this snapshot came from: "app" (the menu bar app's mirror) or "core".
    var origin = "none"

    /// The parsed provider behind a Touch Bar layout entry.
    func provider(for provider: TouchBarProvider) -> Provider {
        switch provider {
        case .claude: return claude
        case .codex: return codex
        case .kimi: return kimi
        case .deepseek: return deepseek
        case .siliconflow: return siliconflow
        case .openrouter: return openrouter
        }
    }
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

    /// How old the app's mirror may be before we fall back to the core layer.
    static let mirrorMaxAge: TimeInterval = 900

    /// Reads a usage snapshot: the menu bar app's mirror when it is fresh, else the
    /// shared core layer. The app is the only side that can reach the SiliconFlow
    /// console session and the Keychain, and the core layer reports SiliconFlow as
    /// `login_required` unconditionally, so preferring the mirror is what makes the
    /// Touch Bar agree with the settings window. Off the main thread.
    static func read() -> Usage {
        if let mirrored = readMirror() { return mirrored }
        return readFromCoreLayer()
    }

    /// The mirror lives beside the shared config file, so both apps agree on it.
    static func mirrorURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment["AI_AGENT_USAGE_CONFIG"], !override.isEmpty {
            return URL(fileURLWithPath: override)
                .deletingLastPathComponent()
                .appendingPathComponent("usage.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ai-agent-usage-widget/usage.json")
    }

    static func isFresh(
        modifiedAt: Date,
        now: Date = Date(),
        maxAge: TimeInterval = UsageSource.mirrorMaxAge
    ) -> Bool {
        let age = now.timeIntervalSince(modifiedAt)
        return age >= -60 && age <= maxAge
    }

    static func readMirror(now: Date = Date()) -> Usage? {
        let url = mirrorURL()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              isFresh(modifiedAt: modified, now: now),
              let data = try? Data(contentsOf: url),
              var usage = usage(from: data) else {
            return nil
        }
        usage.origin = "app"
        usage.updatedAt = modified
        return usage
    }

    /// Parses a shared-contract payload (both the core layer and the app emit one).
    static func usage(from data: Data) -> Usage? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        var usage = Usage()
        usage.claude = provider(from: root["claude"])
        usage.codex  = provider(from: root["codex"])
        usage.kimi   = provider(from: root["kimi"])
        usage.deepseek = provider(from: root["deepseek"])
        usage.siliconflow = provider(from: root["siliconflow"])
        usage.openrouter = provider(from: root["openrouter"])
        usage.updatedAt = Date()
        return usage
    }

    /// Runs the shared fetcher and parses its JSON.
    static func readFromCoreLayer() -> Usage {
        var usage = Usage()
        guard let script = scriptPath() else {
            let p = Provider(ok: false, reason: "no fetcher")
            usage.claude = p; usage.codex = p; usage.kimi = p
            usage.deepseek = p; usage.siliconflow = p; usage.openrouter = p
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
            usage.deepseek = p; usage.siliconflow = p; usage.openrouter = p
            return usage
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard var parsed = UsageSource.usage(from: data) else {
            let p = Provider(ok: false, reason: "bad output")
            usage.claude = p; usage.codex = p; usage.kimi = p
            usage.deepseek = p; usage.siliconflow = p; usage.openrouter = p
            return usage
        }
        parsed.origin = "core"
        return parsed
    }

    private static func provider(from any: Any?) -> Provider {
        guard let o = any as? [String: Any] else { return Provider(ok: false, reason: "missing") }
        var p = Provider(ok: (o["ok"] as? Bool) ?? false)
        p.reason = o["reason"] as? String
        p.kind = o["kind"] as? String
        p.source = o["source"] as? String
        p.fiveH  = window(from: o["five_h"])
        p.weekly = window(from: o["weekly"])
        p.balance = balance(from: o["balance"])
        p.burnRate = burnRate(from: o["burn_rate"])
        if let a = o["as_of"] as? Double { p.asOf = Date(timeIntervalSince1970: a) }
        p.live = o["live"] as? Bool
        if let f = o["fetched_at"] as? Double {
            p.fetchedAt = Date(timeIntervalSince1970: f)
        }
        return p
    }

    private static func window(from any: Any?) -> Window? {
        guard let o = any as? [String: Any], let pct = o["pct"] as? Double else { return nil }
        var reset: Date?
        if let r = o["resets_at"] as? Double { reset = Date(timeIntervalSince1970: r) }
        return Window(usedPct: pct, resetsAt: reset, stale: (o["stale"] as? Bool) ?? false)
    }

    private static func balance(from any: Any?) -> Balance? {
        guard let o = any as? [String: Any],
              let amount = o["amount"] as? Double,
              let currency = o["currency"] as? String
        else { return nil }
        return Balance(
            amount: amount,
            currency: currency,
            available: (o["available"] as? Bool) ?? true,
            label: (o["label"] as? String) ?? "Balance"
        )
    }

    private static func burnRate(from any: Any?) -> BurnRate? {
        guard let o = any as? [String: Any],
              let confidence = o["confidence"] as? String
        else { return nil }
        return BurnRate(
            amountPerDay: o["amount_per_day"] as? Double,
            windowDays: o["window_days"] as? Int,
            estimatedDaysLeft: o["estimated_days_left"] as? Int,
            confidence: confidence,
            reason: o["reason"] as? String
        )
    }
}
