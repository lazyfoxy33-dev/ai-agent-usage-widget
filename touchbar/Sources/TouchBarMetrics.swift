import CoreGraphics

/// Widths for the expanded strip.
///
/// macOS silently drops cells that do not fit. Measured on a 13" MacBook Pro by
/// shrinking cells until nothing was dropped: five cells fit at 110pt but not at
/// 120pt, i.e. the strip offers roughly 600pt to cells once the close button,
/// the reset countdown and the spaces are accounted for. `cellBudget` keeps a
/// margin below that, and `TouchBarController` still retries narrower if a Mac
/// turns out to be tighter than this.
enum TouchBarMetrics {
    /// Width available to the cells themselves (spacing excluded).
    static let cellBudget: CGFloat = 560
    static let maxCellWidth: CGFloat = 170
    static let minCellWidth: CGFloat = 84
    static let spacing: CGFloat = 8
    /// Below this a cell drops its row labels and uses a smaller figure.
    static let compactThreshold: CGFloat = 122

    /// Cell width that keeps `count` cells inside the budget.
    static func cellWidth(for count: Int) -> CGFloat {
        guard count > 0 else { return maxCellWidth }
        let spare = cellBudget - CGFloat(count - 1) * spacing
        let ideal = (spare / CGFloat(count)).rounded(.down)
        return min(maxCellWidth, max(minCellWidth, ideal))
    }

    /// Total width the cells plus their spacing need, for diagnostics.
    static func cellsWidth(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * cellWidth(for: count) + CGFloat(count - 1) * spacing
    }
}
