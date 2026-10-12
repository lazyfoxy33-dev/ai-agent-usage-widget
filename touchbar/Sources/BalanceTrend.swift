import Foundation

/// The trend line a balance cell shows.
///
/// The strip is tiny, so it only prints a figure it can stand behind: a days-left
/// estimate needs at least a full day of comparison history. Below that the
/// extrapolation is a single session's spend (SiliconFlow's first day claimed
/// "约可用 1 天" from 17 hours of samples), so the cell says the estimate is
/// still forming instead.
enum BalanceTrend {
    static func text(for burnRate: BurnRate?) -> String? {
        guard let burnRate, burnRate.confidence != "none" else { return nil }
        guard let days = burnRate.estimatedDaysLeft, days > 0 else { return nil }
        guard (burnRate.windowDays ?? 0) >= 1 else { return "样本不足" }
        return "≈\(days)天"
    }
}
