import AppKit

/// Touch Bar presence:
///   * a small persistent tray cell that glances the AI app you're using —
///     it follows the frontmost Claude / Codex / Kimi app (else the most recent),
///     and falls back to the most-drained window when none has data;
///   * a full-width modal bar with one compact gauge per provider, presented on tap.
/// Percentages are **used %**, matching the Übersicht widget. Data comes from the
/// shared `core/fetch_usage.py` via `UsageSource`.
final class TouchBarController: NSObject, NSTouchBarDelegate {

    private let trayItem = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier(ControlStrip.identifier))
    private let trayButton = NSButton()

    private let closeID  = NSTouchBarItem.Identifier("com.quotabar.close")
    private let claudeID = NSTouchBarItem.Identifier("com.quotabar.claude")
    private let codexID  = NSTouchBarItem.Identifier("com.quotabar.codex")
    private let kimiID   = NSTouchBarItem.Identifier("com.quotabar.kimi")
    private let resetID  = NSTouchBarItem.Identifier("com.quotabar.reset")
    private let resetField = NSTextField(labelWithString: "")
    private var modalBar: NSTouchBar?
    private var modalVisible = false

    // Per-provider gauges hold their own brand palette; built once and reused.
    private lazy var claudeGauge = ProviderGauge(letter: "C", accent: accent("C"), soft: soft("C"))
    private lazy var codexGauge  = ProviderGauge(letter: "X", accent: accent("X"), soft: soft("X"))
    private lazy var kimiGauge   = ProviderGauge(letter: "K", accent: accent("K"), soft: soft("K"))

    private var usage = Usage()
    private let work = DispatchQueue(label: "com.quotabar.fetch")
    private var timer: Timer?
    private let refreshEvery: TimeInterval = 60   // shared layer caches Claude/Kimi 5 min

    // Foreground-aware glance: the collapsed cell tracks whichever AI app is
    // frontmost (Claude / Codex / Kimi desktop apps); when none is, it falls back
    // to the most recently active one (persisted across launches).
    private var foregroundTag: String?
    private var lastUsedTag: String? {
        didSet { UserDefaults.standard.set(lastUsedTag, forKey: "lastUsedTag") }
    }

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
        case "X": return rgb(0x7B, 0x83, 0xF5)   // Codex purple-blue
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

        lastUsedTag = UserDefaults.standard.string(forKey: "lastUsedTag")
        foregroundTag = providerTag(forFrontmost: NSWorkspace.shared.frontmostApplication)
        if let t = foregroundTag { lastUsedTag = t }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
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

    // MARK: Foreground tracking

    @objc private func activeAppChanged() {
        foregroundTag = providerTag(forFrontmost: NSWorkspace.shared.frontmostApplication)
        if let t = foregroundTag { lastUsedTag = t }
        renderTray()
    }

    /// Maps the frontmost desktop app to a provider tag by matching brand keywords
    /// in its bundle id / name. Returns nil for anything that isn't an AI app.
    private func providerTag(forFrontmost app: NSRunningApplication?) -> String? {
        guard let app = app else { return nil }
        let s = ((app.bundleIdentifier ?? "") + " " + (app.localizedName ?? "")).lowercased()
        if s.contains("claude") { return "C" }
        if s.contains("kimi") || s.contains("moonshot") { return "K" }
        if s.contains("codex") || s.contains("openai") || s.contains("chatgpt") { return "X" }
        return nil
    }

    private func presentModal() {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [
            closeID, .fixedSpaceLarge,
            claudeID, .fixedSpaceSmall, codexID, .fixedSpaceSmall, kimiID,
            .flexibleSpace, resetID,
        ]
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
        case claudeID: return gaugeItem(id, claudeGauge)
        case codexID:  return gaugeItem(id, codexGauge)
        case kimiID:   return gaugeItem(id, kimiGauge)
        case resetID:
            let it = NSCustomTouchBarItem(identifier: id)
            resetField.font = detailFont
            resetField.lineBreakMode = .byClipping
            resetField.maximumNumberOfLines = 1
            it.view = resetField
            return it
        default:
            return nil
        }
    }

    private func gaugeItem(_ id: NSTouchBarItem.Identifier, _ view: ProviderGauge) -> NSTouchBarItem {
        let it = NSCustomTouchBarItem(identifier: id)
        it.view = view
        it.visibilityPriority = .high
        return it
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
        let s = NSMutableAttributedString()
        // Prefer the AI app you're using (foreground, else most-recent). When that
        // provider has no usable window, fall back to the most-drained one overall.
        let pick = (foregroundTag ?? lastUsedTag).flatMap { tag in
            tightest(forTag: tag).map { (tag, $0) }
        } ?? tightestOverall()
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

    /// Most-drained live window for one provider. Prefers non-stale figures.
    private func tightest(forTag tag: String) -> Window? {
        let wins = liveWindows().filter { $0.0 == tag }
        return (wins.filter { !$0.1.stale }.max(by: { $0.1.usedPct < $1.1.usedPct })
             ?? wins.max(by: { $0.1.usedPct < $1.1.usedPct }))?.1
    }

    /// Most-drained live window across all providers.
    private func tightestOverall() -> (String, Window)? {
        let wins = liveWindows()
        return wins.filter { !$0.1.stale }.max(by: { $0.1.usedPct < $1.1.usedPct })
            ?? wins.max(by: { $0.1.usedPct < $1.1.usedPct })
    }

    // MARK: Rendering — detail (modal, full width)

    private func renderDetail() {
        feed(claudeGauge, usage.claude)
        feed(codexGauge,  usage.codex)
        feed(kimiGauge,   usage.kimi)

        if let reset = soonestReset() {
            let s = NSMutableAttributedString()
            s.append(seg("⟳ ", detailFont, dim))
            s.append(seg(countdown(reset), detailFont, bright))
            resetField.attributedStringValue = s
        } else {
            resetField.attributedStringValue = NSAttributedString(string: "")
        }
    }

    private func feed(_ gauge: ProviderGauge, _ p: Provider) {
        guard p.ok, (p.fiveH != nil || p.weekly != nil) else {
            gauge.update(ok: false, status: status(p), fiveH: nil, weekly: nil, cached: false)
            return
        }
        let cached = p.reason == "stale" || p.live == false
        gauge.update(ok: true, status: "",
                     fiveH:  p.fiveH.map  { ($0.usedPct, $0.stale) },
                     weekly: p.weekly.map { ($0.usedPct, $0.stale) },
                     cached: cached)
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
