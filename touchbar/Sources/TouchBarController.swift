import AppKit

/// Touch Bar presence:
///   * a small persistent tray cell showing the single most-used quota (glance);
///   * a full-width modal bar with Claude / Codex / Kimi detail, presented on tap.
/// Percentages are **used %**, matching the Übersicht widget. Data comes from the
/// shared `core/fetch_usage.py` via `UsageSource`.
final class TouchBarController: NSObject, NSTouchBarDelegate {

    private let trayItem = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier(ControlStrip.identifier))
    private let trayButton = NSButton()

    private let detailID = NSTouchBarItem.Identifier("com.quotabar.detail")
    private let closeID  = NSTouchBarItem.Identifier("com.quotabar.close")
    private let detailField = NSTextField(labelWithString: "")
    private var detailWidthConstraint: NSLayoutConstraint?
    private var modalBar: NSTouchBar?
    private var modalVisible = false

    private var usage = Usage()
    private let work = DispatchQueue(label: "com.quotabar.fetch")
    private var timer: Timer?
    private let refreshEvery: TimeInterval = 60   // shared layer caches Claude/Kimi 5 min

    // Visual tuning
    private let trayFont   = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
    private let detailFont = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .medium)
    private let dim    = NSColor(white: 0.55, alpha: 1)
    private let bright = NSColor(white: 0.92, alpha: 1)

    // Per-provider brand palette, matching the Übersicht widget (5h = accent,
    // weekly = softer tint). C=Claude, X=Codex, K=Kimi.
    private func accent(_ tag: String) -> NSColor {
        switch tag {
        case "C": return rgb(0xD9, 0x77, 0x57)   // Claude terracotta
        case "X": return rgb(0x66, 0x76, 0xFF)   // Codex blue
        case "K": return rgb(0x2E, 0x8B, 0xFF)   // Kimi blue (brightened for dark bar)
        default:  return bright
        }
    }
    private func soft(_ tag: String) -> NSColor {
        switch tag {
        case "C": return rgb(0xE3, 0xA7, 0x7F)   // Claude soft
        case "X": return rgb(0xA7, 0x8B, 0xFA)   // Codex purple
        case "K": return rgb(0x7F, 0xB3, 0xFF)   // Kimi soft
        default:  return dim
        }
    }
    private func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
    }

    // MARK: Lifecycle

    func start() {
        trayButton.isBordered = false
        trayButton.title = ""
        trayButton.target = self
        trayButton.action = #selector(trayTapped)
        trayButton.imagePosition = .noImage
        trayButton.translatesAutoresizingMaskIntoConstraints = true
        trayButton.frame = NSRect(x: 0, y: 0, width: 56, height: 30)
        trayItem.view = trayButton

        if !ControlStrip.install(trayItem) {
            NSLog("QuotaBar: control strip hooks unavailable on this system")
        }
        renderTray()

        timer = Timer.scheduledTimer(withTimeInterval: refreshEvery, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    // MARK: Interaction

    @objc private func trayTapped() {
        if modalVisible { minimizeModal() } else { presentModal() }
    }

    @objc private func closeTapped() { minimizeModal() }

    private func presentModal() {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [closeID, .fixedSpaceSmall, detailID]
        bar.principalItemIdentifier = detailID
        modalBar = bar
        renderDetail()
        ControlStrip.presentModal(bar)
        modalVisible = true
    }

    private func minimizeModal() {
        if let bar = modalBar { ControlStrip.minimizeModal(bar) }
        modalVisible = false
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch id {
        case closeID:
            let b = NSButton(title: "✕", target: self, action: #selector(closeTapped))
            b.bezelColor = NSColor(white: 0.2, alpha: 1)
            let it = NSCustomTouchBarItem(identifier: id)
            it.view = b
            return it
        case detailID:
            let it = NSCustomTouchBarItem(identifier: id)
            detailField.font = detailFont
            detailField.lineBreakMode = .byClipping
            detailField.maximumNumberOfLines = 1
            detailField.translatesAutoresizingMaskIntoConstraints = false
            detailWidthConstraint?.isActive = false
            detailWidthConstraint = detailField.widthAnchor.constraint(
                greaterThanOrEqualToConstant: 900
            )
            detailWidthConstraint?.isActive = true
            it.view = detailField
            it.visibilityPriority = .high
            return it
        default:
            return nil
        }
    }

    // MARK: Refresh

    private func refresh() {
        work.async { [weak self] in
            guard let self = self else { return }
            let fresh = UsageSource.read()
            DispatchQueue.main.async {
                self.usage = fresh
                self.renderTray()
                if self.modalVisible { self.renderDetail() }
            }
        }
    }

    // MARK: Rendering — tray (collapsed)

    /// (tag, window) for every live window across providers, used to surface the
    /// most-drained one at a glance.
    private func liveWindows() -> [(String, Window)] {
        var out: [(String, Window)] = []
        func add(_ tag: String, _ p: Provider) {
            guard p.ok else { return }
            if var w = p.fiveH {
                w.stale = w.stale || p.live == false
                out.append((tag, w))
            }
            if var w = p.weekly {
                w.stale = w.stale || p.live == false
                out.append((tag, w))
            }
        }
        add("C", usage.claude); add("X", usage.codex); add("K", usage.kimi)
        return out
    }

    private func renderTray() {
        let wins = liveWindows()
        let s = NSMutableAttributedString()
        // Tightest = highest used %. Prefer non-stale data for a trustworthy glance.
        let pick = wins.filter { !$0.1.stale }.max(by: { $0.1.usedPct < $1.1.usedPct })
                ?? wins.max(by: { $0.1.usedPct < $1.1.usedPct })
        if let (tag, w) = pick {
            let pct = Int(w.usedPct.rounded())
            s.append(seg(tag, trayFont, w.stale ? dim : accent(tag)))
            s.append(seg(String(pct), trayFont, w.stale ? dim : accent(tag)))
        } else {
            s.append(seg("··", trayFont, dim))
        }
        trayButton.attributedTitle = s
        let width = ceil(s.size().width) + 16
        trayButton.frame = NSRect(x: 0, y: 0, width: max(width, 40), height: 30)
    }

    // MARK: Rendering — detail (modal, full width)

    private func renderDetail() {
        let s = NSMutableAttributedString()
        append(s, "Claude", "C", usage.claude)
        s.append(seg("    ", detailFont, dim))
        append(s, "Codex", "X", usage.codex)
        s.append(seg("    ", detailFont, dim))
        append(s, "Kimi", "K", usage.kimi)

        if let reset = soonestReset() {
            s.append(seg("   ⟳ ", detailFont, dim))
            s.append(seg(countdown(reset), detailFont, bright))
        }
        detailField.attributedStringValue = s
    }

    private func append(_ s: NSMutableAttributedString, _ name: String, _ tag: String, _ p: Provider) {
        s.append(seg(name + " ", detailFont, accent(tag)))
        guard p.ok, (p.fiveH != nil || p.weekly != nil) else {
            s.append(seg(status(p), detailFont, dim))
            return
        }
        s.append(seg("5h ", detailFont, dim));  s.append(pct(p.fiveH, accent(tag)))
        s.append(seg(" 7d ", detailFont, dim)); s.append(pct(p.weekly, soft(tag)))
        if p.reason == "stale" || p.live == false {
            s.append(seg(" ·缓存", detailFont, dim))
        }
    }

    private func pct(_ w: Window?, _ base: NSColor) -> NSAttributedString {
        guard let w = w else { return seg("–", detailFont, dim) }
        let v = "\(Int(w.usedPct.rounded()))%"
        return seg(v, detailFont, w.stale ? dim : base)
    }

    private func soonestReset() -> Date? {
        let now = Date()
        return liveWindows().compactMap { $0.1.resetsAt }.filter { $0 > now }.min()
    }

    // MARK: Helpers

    private func status(_ p: Provider) -> String {
        switch p.reason {
        case "expired": return "登录过期"
        case "rate_limited": return "请求受限"
        case "no_data": return "无数据"
        case "loading": return "…"
        default:        return "获取失败"
        }
    }

    private func countdown(_ date: Date) -> String {
        let secs = Int(date.timeIntervalSinceNow)
        if secs <= 0 { return "now" }
        let h = secs / 3600, m = (secs % 3600) / 60
        if h >= 24 { let d = h / 24; return "\(d)d\(h % 24)h" }
        return h > 0 ? "\(h)h\(String(format: "%02d", m))m" : "\(m)m"
    }

    private func seg(_ text: String, _ font: NSFont, _ color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }
}
