import AppKit

extension NSColor {
    /// In-hue emphasis for a dark (always black) Touch Bar background.
    /// Level 0 returns the accent unchanged; level 1/2 brighten the color
    /// toward white without shifting hue.
    func emphasized(by usedPct: Double) -> NSColor {
        let level: Int
        if usedPct >= 90 { level = 2 }
        else if usedPct >= 70 { level = 1 }
        else { level = 0 }
        if level == 0 { return self }

        guard let c = usingColorSpace(.sRGB) else { return self }
        let t: CGFloat = [0, 0.20, 0.38][level]
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        let brighten = { (v: CGFloat) -> CGFloat in v + (1.0 - v) * t }
        return NSColor(srgbRed: brighten(r), green: brighten(g), blue: brighten(b), alpha: a)
    }
}

/// One provider's compact Touch Bar gauge. It translates the menu bar app's
/// two-ring design (5h = accent, weekly = soft tint) onto the horizontal strip as
/// a brand badge plus two mini bars. Fixed width keeps the modal's total length
/// bounded; rendering stays inside the Touch Bar's 30pt height.
final class ProviderGauge: NSView {

    // Identity / palette (passed in from the controller so colors stay in one place).
    private let letter: String
    private let accent: NSColor
    private let soft: NSColor
    private let track = NSColor(white: 1, alpha: 0.16)
    private let dim   = NSColor(white: 0.55, alpha: 1)
    private let badgeInk = NSColor(white: 0.07, alpha: 1)

    // Snapshot of what to draw, set by `update` / `updateBalance`.
    private var ok = false
    private var statusText = ""
    private var fiveH:  (pct: Double, stale: Bool)?
    private var weekly: (pct: Double, stale: Bool)?
    // Balance providers show an amount plus a trend/state line instead of bars.
    private var balanceMode = false
    private var amountText = ""
    private var detailText = ""

    // Fonts
    private let badgeFont = NSFont.systemFont(ofSize: 12, weight: .heavy)
    private let microFont = NSFont.systemFont(ofSize: 8,  weight: .semibold)
    private let weeklyMicroFont = NSFont.systemFont(ofSize: 6,  weight: .semibold)
    private let pctFont   = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    private let statusFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    private let amountFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    private let detailFont = NSFont.systemFont(ofSize: 8.5, weight: .medium)

    // Layout constants
    private let badgeX: CGFloat = 6, badgeSize: CGFloat = 20
    private var textX: CGFloat { badgeX + badgeSize + 8 }      // 34
    private let microW: CGFloat = 17
    /// The bar takes whatever is left once the label and the figure have room.
    private var barW: CGFloat { max(22, width - 88) }
    private let barH: CGFloat = 4
    private let rowTopY: CGFloat = 20, rowBottomY: CGFloat = 10

    /// Card width; the strip narrows cards when many providers are selected.
    private(set) var width: CGFloat = 170
    private var widthConstraint: NSLayoutConstraint?

    init(letter: String, accent: NSColor, soft: NSColor) {
        self.letter = letter
        self.accent = accent
        self.soft = soft
        super.init(frame: NSRect(x: 0, y: 0, width: 170, height: 30))
        wantsLayer = true
        // Touch Bar items lay out with Auto Layout; let intrinsicContentSize drive width.
        translatesAutoresizingMaskIntoConstraints = false
        let constraint = widthAnchor.constraint(equalToConstant: width)
        constraint.isActive = true
        widthConstraint = constraint
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func setWidth(_ newWidth: CGFloat) {
        guard abs(newWidth - width) > 0.5 else { return }
        width = newWidth
        widthConstraint?.constant = newWidth
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: 30) }
    override var allowsVibrancy: Bool { false }

    /// `cached` dims the whole card (provider serving non-live data); per-window
    /// `stale` (window already reset) dims just that bar + figure.
    func update(ok: Bool, status: String,
                fiveH: (Double, Bool)?, weekly: (Double, Bool)?, cached: Bool) {
        self.ok = ok
        self.statusText = status
        self.fiveH  = fiveH.map  { (pct: $0.0, stale: $0.1) }
        self.weekly = weekly.map { (pct: $0.0, stale: $0.1) }
        self.balanceMode = false
        self.alphaValue = cached ? 0.62 : 1
        needsDisplay = true
    }

    /// Balance variant: the amount on the first row, a trend or state line below.
    func updateBalance(ok: Bool, status: String, amount: String, detail: String, cached: Bool) {
        self.ok = ok
        self.statusText = status
        self.fiveH = nil
        self.weekly = nil
        self.balanceMode = true
        self.amountText = amount
        self.detailText = detail
        self.alphaValue = cached ? 0.62 : 1
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Card: faint brand-tinted plate, grouping the provider as the widget rows do.
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: 8, yRadius: 8)
        accent.withAlphaComponent(0.08).setFill();  card.fill()
        accent.withAlphaComponent(0.22).setStroke(); card.lineWidth = 0.6; card.stroke()

        // Brand badge with the provider initial.
        let badge = NSBezierPath(roundedRect: NSRect(x: badgeX, y: (30 - badgeSize) / 2,
                                                     width: badgeSize, height: badgeSize),
                                 xRadius: 6, yRadius: 6)
        (ok ? accent : accent.withAlphaComponent(0.45)).setFill(); badge.fill()
        let bl = NSAttributedString(string: letter,
                                    attributes: [.font: badgeFont, .foregroundColor: badgeInk])
        let bsz = bl.size()
        bl.draw(at: NSPoint(x: badgeX + (badgeSize - bsz.width) / 2,
                            y: (30 - bsz.height) / 2 + 0.5))

        guard ok else {
            let st = NSAttributedString(string: statusText,
                                        attributes: [.font: statusFont, .foregroundColor: dim])
            st.draw(at: NSPoint(x: textX, y: (30 - st.size().height) / 2))
            return
        }

        if balanceMode {
            balanceRows()
            return
        }

        row("5H", fiveH,  base: accent, centerY: rowTopY)
        row("Wk", weekly, base: soft,   centerY: rowBottomY)
    }

    /// Amount line + small trend/state line, aligned to the quota gauge rows.
    private func balanceRows() {
        let amountColor = accent.emphasized(by: 0)
        let amount = NSAttributedString(
            string: amountText,
            attributes: [.font: amountFont, .foregroundColor: amountColor])
        amount.draw(at: NSPoint(x: textX, y: rowTopY - amount.size().height / 2))

        guard !detailText.isEmpty else { return }
        let detail = NSAttributedString(
            string: detailText,
            attributes: [.font: detailFont, .foregroundColor: dim])
        detail.draw(at: NSPoint(x: textX, y: rowBottomY - detail.size().height / 2))
    }

    private func row(_ label: String, _ win: (pct: Double, stale: Bool)?,
                     base: NSColor, centerY: CGFloat) {
        let color = (win?.stale ?? false) ? dim : base.emphasized(by: win?.pct ?? 0)

        let labelFont = label.count > 2 ? weeklyMicroFont : microFont
        let micro = NSAttributedString(string: label,
                                       attributes: [.font: labelFont, .foregroundColor: dim])
        micro.draw(at: NSPoint(x: textX, y: centerY - micro.size().height / 2))

        let barX = textX + microW
        let trackRect = NSRect(x: barX, y: centerY - barH / 2, width: barW, height: barH)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: barH / 2, yRadius: barH / 2)
        track.setFill(); trackPath.fill()

        if let pct = win?.pct {
            let frac = max(0, min(100, pct)) / 100
            let fillW = max(barH, barW * CGFloat(frac))   // keep a rounded nub at low %
            let fillPath = NSBezierPath(
                roundedRect: NSRect(x: barX, y: centerY - barH / 2, width: fillW, height: barH),
                xRadius: barH / 2, yRadius: barH / 2)
            color.setFill(); fillPath.fill()
        }

        let text = win.map { "\(Int($0.pct.rounded()))%" } ?? "–"
        let pctStr = NSAttributedString(string: text,
                                        attributes: [.font: pctFont, .foregroundColor: color])
        pctStr.draw(at: NSPoint(x: barX + barW + 7, y: centerY - pctStr.size().height / 2))
    }
}
