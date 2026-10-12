import Foundation

/// The trend line a balance cell shows.
///
/// The shared layer averages the trailing day and reports `insufficient_history`
/// until it has six hours of samples, so the cell shows whatever real estimate it
/// is given (a young history is a low-confidence recent average, not a guess) and
/// says the estimate is still forming only when the estimator says so.
enum BalanceTrend {
    static func text(for burnRate: BurnRate?) -> String? {
        guard let burnRate else { return nil }
        if burnRate.confidence == "none" {
            return burnRate.reason == "insufficient_history" ? "样本不足" : nil
        }
        guard let days = burnRate.estimatedDaysLeft else { return nil }
        return days > 0 ? "≈\(days)天" : "不足1天"
    }
}
