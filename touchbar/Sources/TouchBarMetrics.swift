import CoreGraphics

/// Widths for the expanded strip.
///
/// macOS silently drops Touch Bar items that do not fit, so cells have to shrink
/// as more providers are selected: three providers keep the original 170pt card,
/// and beyond that they compress towards a still-legible minimum.
enum TouchBarMetrics {
    /// Usable width of the system modal strip (a 13" MacBook Pro strip is about
    /// 1004pt wide; the budget keeps ~5% back so nothing gets dropped).
    static let barWidth: CGFloat = 960
    /// Close button, reset countdown and the spaces around them.
    static let chromeWidth: CGFloat = 210
    static let maxCellWidth: CGFloat = 170
    static let minCellWidth: CGFloat = 96
    static let spacing: CGFloat = 8

    /// Cell width that keeps `count` cells inside the strip.
    static func cellWidth(for count: Int) -> CGFloat {
        guard count > 0 else { return maxCellWidth }
        let spare = barWidth - chromeWidth - CGFloat(count - 1) * spacing
        let ideal = (spare / CGFloat(count)).rounded(.down)
        return min(maxCellWidth, max(minCellWidth, ideal))
    }

    /// Total width `count` cells plus the chrome need, for diagnostics.
    static func totalWidth(for count: Int) -> CGFloat {
        guard count > 0 else { return chromeWidth }
        return CGFloat(count) * cellWidth(for: count) + CGFloat(count - 1) * spacing + chromeWidth
    }
}
