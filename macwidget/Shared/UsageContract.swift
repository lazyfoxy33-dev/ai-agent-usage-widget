import Foundation

enum WidgetLayout {
    static let mediumRingSize: CGFloat = 50
}

struct UsageWindow: Codable, Equatable {
    let percentage: Double
    let resetsAt: TimeInterval?
    let stale: Bool?

    init(percentage: Double, resetsAt: TimeInterval? = nil, stale: Bool? = nil) {
        self.percentage = percentage
        self.resetsAt = resetsAt
        self.stale = stale
    }

    enum CodingKeys: String, CodingKey {
        case percentage = "pct"
        case resetsAt = "resets_at"
        case stale
    }
}

struct UsageProvider: Codable, Equatable {
    let ok: Bool
    let reason: String?
    let live: Bool?
    let fetchedAt: TimeInterval?
    let asOf: TimeInterval?
    let fiveH: UsageWindow?
    let weekly: UsageWindow?

    init(
        ok: Bool,
        reason: String? = nil,
        live: Bool? = nil,
        fetchedAt: TimeInterval? = nil,
        asOf: TimeInterval? = nil,
        fiveH: UsageWindow? = nil,
        weekly: UsageWindow? = nil
    ) {
        self.ok = ok
        self.reason = reason
        self.live = live
        self.fetchedAt = fetchedAt
        self.asOf = asOf
        self.fiveH = fiveH
        self.weekly = weekly
    }

    var isStale: Bool {
        live == false || reason == "stale"
            || fiveH?.stale == true || weekly?.stale == true
    }

    enum CodingKeys: String, CodingKey {
        case ok, reason, live
        case fetchedAt = "fetched_at"
        case asOf = "as_of"
        case fiveH = "five_h"
        case weekly
    }
}

struct UsagePayload: Codable, Equatable {
    let schemaVersion: Int
    let claude: UsageProvider
    let codex: UsageProvider
    let kimi: UsageProvider

    static func decode(_ data: Data) throws -> UsagePayload {
        try JSONDecoder().decode(UsagePayload.self, from: data)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case claude, codex, kimi
    }
}

enum ProviderKind: String, CaseIterable {
    case claude = "Claude"
    case codex = "Codex"
    case kimi = "Kimi Code"
}

enum ProviderPresentation {
    private struct Strings {
        let rateLimited: String
        let notSignedIn: String
        let cached: String
        let cmdMap: [String: String]
    }

    private static let zh = Strings(
        rateLimited: "请求受限 · 稍后自动重试",
        notSignedIn: "未登录 · 请先在 {CLI} 登录",
        cached: "缓存数据 · 等待刷新",
        cmdMap: [
            "Claude": "Claude Code",
            "Codex": "Codex CLI",
            "Kimi Code": "Kimi CLI"
        ]
    )

    private static let en = Strings(
        rateLimited: "Rate limited · retrying soon",
        notSignedIn: "Not signed in · Log in via {CLI}",
        cached: "Cached · awaiting refresh",
        cmdMap: [
            "Claude": "Claude Code",
            "Codex": "Codex CLI",
            "Kimi Code": "Kimi CLI"
        ]
    )

    private static var strings: Strings {
        let code = Locale.current.language.languageCode?.identifier ?? "zh"
        return code.hasPrefix("en") ? en : zh
    }

    static func message(for kind: ProviderKind, provider: UsageProvider) -> String {
        switch provider.reason {
        case "rate_limited":
            return strings.rateLimited
        default:
            let cli = strings.cmdMap[kind.rawValue] ?? kind.rawValue
            return strings.notSignedIn.replacingOccurrences(of: "{CLI}", with: cli)
        }
    }

    static func cachedMessage() -> String {
        strings.cached
    }

    static func code(for label: String) -> String {
        label == "Weekly" ? "Wk" : label
    }

    static func countdown(until timestamp: TimeInterval?, now: Date = Date()) -> String {
        guard let timestamp else { return "Resets soon" }
        let seconds = max(0, Int(timestamp - now.timeIntervalSince1970))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func soonest(
        provider: UsageProvider,
        now: Date = Date()
    ) -> (code: String, text: String) {
        let windows = [
            (label: "5H", resetsAt: provider.fiveH?.resetsAt),
            (label: "Weekly", resetsAt: provider.weekly?.resetsAt)
        ]
        let nearest = windows.min {
            let a = $0.resetsAt ?? Double.infinity
            let b = $1.resetsAt ?? Double.infinity
            return a < b
        } ?? windows[0]
        return (
            code: code(for: nearest.label),
            text: countdown(until: nearest.resetsAt, now: now)
        )
    }
}

extension UsagePayload {
    static let preview = UsagePayload(
        schemaVersion: 1,
        claude: UsageProvider(
            ok: true, live: true,
            fiveH: UsageWindow(percentage: 42, resetsAt: Date().timeIntervalSince1970 + 7_200),
            weekly: UsageWindow(percentage: 18, resetsAt: Date().timeIntervalSince1970 + 400_000)
        ),
        codex: UsageProvider(
            ok: true, live: true,
            fiveH: UsageWindow(percentage: 28, resetsAt: Date().timeIntervalSince1970 + 9_000),
            weekly: UsageWindow(percentage: 12, resetsAt: Date().timeIntervalSince1970 + 500_000)
        ),
        kimi: UsageProvider(
            ok: true, live: true,
            fiveH: UsageWindow(percentage: 36, resetsAt: Date().timeIntervalSince1970 + 12_000),
            weekly: UsageWindow(percentage: 9, resetsAt: Date().timeIntervalSince1970 + 600_000)
        )
    )
}
