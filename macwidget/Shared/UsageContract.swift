import Foundation

enum WidgetLayout {
    static let mediumRingSize: CGFloat = 54
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
    static func message(for kind: ProviderKind, provider: UsageProvider) -> String {
        switch provider.reason {
        case "rate_limited":
            return "请求受限 · 稍后自动重试"
        case "expired" where kind == .kimi:
            return "登录态过期 · 去 Kimi CLI 重新登录"
        case "expired":
            return "登录态过期 · 去 Claude Code 重新登录"
        case "no_data" where kind == .kimi:
            return "未登录 · 先在 Kimi CLI 完成登录"
        case "no_data" where kind == .codex:
            return "暂无数据 · 先使用一次 Codex"
        default:
            return "暂无数据"
        }
    }

    static func countdown(until timestamp: TimeInterval?, now: Date = Date()) -> String {
        guard let timestamp else { return "重置时间未知" }
        let seconds = max(0, Int(timestamp - now.timeIntervalSince1970))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时后重置" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分后重置" }
        return "\(minutes) 分后重置"
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
