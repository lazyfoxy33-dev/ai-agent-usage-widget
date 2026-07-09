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

struct BalanceInfo: Codable, Equatable {
    let amount: Double
    let currency: String
    let available: Bool
    let label: String
}

struct BurnRateInfo: Codable, Equatable {
    let amountPerDay: Double?
    let windowDays: Int?
    let estimatedDaysLeft: Int?
    let confidence: String
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case amountPerDay = "amount_per_day"
        case windowDays = "window_days"
        case estimatedDaysLeft = "estimated_days_left"
        case confidence
        case reason
    }
}

struct UsageProvider: Codable, Equatable {
    let ok: Bool
    let reason: String?
    let kind: String?
    let source: String?
    let live: Bool?
    let fetchedAt: TimeInterval?
    let asOf: TimeInterval?
    let fiveH: UsageWindow?
    let weekly: UsageWindow?
    let balance: BalanceInfo?
    let burnRate: BurnRateInfo?

    init(
        ok: Bool,
        reason: String? = nil,
        kind: String? = nil,
        source: String? = nil,
        live: Bool? = nil,
        fetchedAt: TimeInterval? = nil,
        asOf: TimeInterval? = nil,
        fiveH: UsageWindow? = nil,
        weekly: UsageWindow? = nil,
        balance: BalanceInfo? = nil,
        burnRate: BurnRateInfo? = nil
    ) {
        self.ok = ok
        self.reason = reason
        self.kind = kind
        self.source = source
        self.live = live
        self.fetchedAt = fetchedAt
        self.asOf = asOf
        self.fiveH = fiveH
        self.weekly = weekly
        self.balance = balance
        self.burnRate = burnRate
    }

    var isStale: Bool {
        live == false || reason == "stale"
            || fiveH?.stale == true || weekly?.stale == true
    }

    enum CodingKeys: String, CodingKey {
        case ok, reason, kind, source, live
        case fetchedAt = "fetched_at"
        case asOf = "as_of"
        case fiveH = "five_h"
        case weekly
        case balance
        case burnRate = "burn_rate"
    }
}

struct UsagePayload: Codable, Equatable {
    let schemaVersion: Int
    let claude: UsageProvider
    let codex: UsageProvider
    let kimi: UsageProvider
    let deepseek: UsageProvider
    let siliconflow: UsageProvider
    let openrouter: UsageProvider

    static func decode(_ data: Data) throws -> UsagePayload {
        try JSONDecoder().decode(UsagePayload.self, from: data)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case claude, codex, kimi, deepseek, siliconflow, openrouter
    }
}

enum ProviderKind: String, CaseIterable {
    case claude = "Claude"
    case codex = "Codex"
    case kimi = "Kimi Code"
    case deepseek = "DeepSeek"
    case siliconflow = "SiliconFlow"
    case openrouter = "OpenRouter"
}

enum ProviderPresentation {
    private struct Strings {
        let rateLimited: String
        let notSignedIn: String
        let noApiKey: String
        let balanceUnavailable: String
        let loginRequired: String
        let invalidSubject: String
        let cached: String
        let cachedBalance: String
        let cmdMap: [String: String]
    }

    private static let zh = Strings(
        rateLimited: "请求受限 · 稍后自动重试",
        notSignedIn: "未登录 · 请先在 {CLI} 登录",
        noApiKey: "未配置 API Key · 请在 {CLI} 添加",
        balanceUnavailable: "余额口径异常 · 请到后台核对",
        loginRequired: "需要重新登录 SiliconFlow 后台",
        invalidSubject: "SiliconFlow 账户标识失效 · 请重新连接",
        cached: "缓存数据 · 等待刷新",
        cachedBalance: "缓存余额 · 等待刷新",
        cmdMap: [
            "Claude": "Claude Code",
            "Codex": "Codex CLI",
            "Kimi Code": "Kimi CLI",
            "DeepSeek": "DeepSeek",
            "SiliconFlow": "SiliconFlow",
            "OpenRouter": "OpenRouter"
        ]
    )

    private static let en = Strings(
        rateLimited: "Rate limited · retrying soon",
        notSignedIn: "Not signed in · Log in via {CLI}",
        noApiKey: "API key not set · Add it in {CLI}",
        balanceUnavailable: "Balance unavailable · check provider console",
        loginRequired: "Sign in to SiliconFlow console again",
        invalidSubject: "SiliconFlow account id expired · reconnect",
        cached: "Cached · awaiting refresh",
        cachedBalance: "Cached balance · awaiting refresh",
        cmdMap: [
            "Claude": "Claude Code",
            "Codex": "Codex CLI",
            "Kimi Code": "Kimi CLI",
            "DeepSeek": "DeepSeek",
            "SiliconFlow": "SiliconFlow",
            "OpenRouter": "OpenRouter"
        ]
    )

    private static var strings: Strings {
        let code = Locale.current.language.languageCode?.identifier ?? "zh"
        return code.hasPrefix("en") ? en : zh
    }

    private static func isBalanceProvider(_ kind: ProviderKind, provider: UsageProvider) -> Bool {
        switch kind {
        case .deepseek, .siliconflow, .openrouter:
            return true
        default:
            return provider.kind == "balance"
        }
    }

    static func message(for kind: ProviderKind, provider: UsageProvider) -> String {
        switch provider.reason {
        case "rate_limited":
            return strings.rateLimited
        case "balance_unavailable":
            return strings.balanceUnavailable
        case "login_required":
            return strings.loginRequired
        case "invalid_subject":
            return strings.invalidSubject
        default:
            let cli = strings.cmdMap[kind.rawValue] ?? kind.rawValue
            if isBalanceProvider(kind, provider: provider) {
                return strings.noApiKey.replacingOccurrences(of: "{CLI}", with: cli)
            }
            return strings.notSignedIn.replacingOccurrences(of: "{CLI}", with: cli)
        }
    }

    static func cachedMessage() -> String {
        strings.cached
    }

    static func cachedBalanceMessage() -> String {
        strings.cachedBalance
    }

    static func balanceAmount(_ balance: BalanceInfo?) -> String {
        guard let balance else { return "–" }
        let amount = String(format: "%.2f", balance.amount)
        switch balance.currency.uppercased() {
        case "CNY":
            return "¥\(amount)"
        case "USD":
            return "$\(amount)"
        default:
            return "\(amount) \(balance.currency.uppercased())"
        }
    }

    static func balanceTrend(_ burnRate: BurnRateInfo?) -> String {
        guard
            let burnRate,
            burnRate.confidence != "none",
            let days = burnRate.estimatedDaysLeft
        else {
            return strings.notSignedIn.hasPrefix("Not") ? "No spending trend yet" : "暂无消耗趋势"
        }
        let window = burnRate.windowDays ?? 7
        return strings.notSignedIn.hasPrefix("Not")
            ? "≈ \(days)d left (\(window)d)"
            : "近 \(window) 日约可用 \(days) 天"
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
        ),
        deepseek: UsageProvider(
            ok: true,
            kind: "balance",
            live: true,
            balance: BalanceInfo(amount: 110.0, currency: "CNY", available: true, label: "Balance"),
            burnRate: BurnRateInfo(
                amountPerDay: 3.2,
                windowDays: 7,
                estimatedDaysLeft: 34,
                confidence: "medium",
                reason: nil
            )
        ),
        siliconflow: UsageProvider(
            ok: true,
            reason: "stale",
            kind: "balance",
            source: "console_session",
            live: false,
            balance: BalanceInfo(amount: 88.88, currency: "CNY", available: true, label: "Balance"),
            burnRate: BurnRateInfo(
                amountPerDay: nil,
                windowDays: nil,
                estimatedDaysLeft: nil,
                confidence: "none",
                reason: "insufficient_history"
            )
        ),
        openrouter: UsageProvider(
            ok: false,
            reason: "no_data",
            kind: "balance",
            live: false
        )
    )
}
