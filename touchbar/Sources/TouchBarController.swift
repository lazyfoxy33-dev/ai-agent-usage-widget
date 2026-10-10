import AppKit

/// Touch Bar presence:
///   * a small persistent tray cell that glances the coding tool you're using —
///     it follows the frontmost Claude / Codex / Kimi app (else the most recent),
///     then the most-drained window. This cell ignores the Touch Bar selection:
///     it always answers "what is the tool in front of me doing";
///   * a full-width modal bar with one compact gauge per **selected** provider,
///     in the configured order, presented on tap.
/// The selection and its order come from the shared config
/// (`touchbar_providers`, written by the menu bar app) and are re-read on every
/// refresh. Percentages are **used %**, matching the menu bar app. Data comes
/// from the shared `core/fetch_usage.py` via `UsageSource`.
final class TouchBarController: NSObject, NSTouchBarDelegate {

    private let trayItem = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier(ControlStrip.identifier))
    private let trayButton = NSButton()

    private let closeID = NSTouchBarItem.Identifier("com.quotabar.close")
    private let resetID = NSTouchBarItem.Identifier("com.quotabar.reset")
    private let resetField = NSTextField(labelWithString: "")
    private var modalBar: NSTouchBar?
    private var modalVisible = false

    /// Providers to show, in display order (re-read from config on refresh).
    private var layout: [TouchBarProvider] = TouchBarLayout.load()
    private var gauges: [TouchBarProvider: ProviderGauge] = [:]

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

    // MARK: Provider identity

    private func itemID(_ provider: TouchBarProvider) -> NSTouchBarItem.Identifier {
        NSTouchBarItem.Identifier("com.quotabar.\(provider.rawValue)")
    }

    private func provider(for id: NSTouchBarItem.Identifier) -> TouchBarProvider? {
        TouchBarProvider.allCases.first { itemID($0) == id }
    }

    private func gauge(for provider: TouchBarProvider) -> ProviderGauge {
        if let existing = gauges[provider] { return existing }
        let created = ProviderGauge(
            letter: provider.tag,
            accent: accent(provider.tag),
            soft: soft(provider.tag)
        )
        gauges[provider] = created
        return created
    }

    /// Fresh views for the current selection: an NSCustomTouchBarItem takes
    /// ownership of its view, so a gauge must not be reused by a later bar.
    private func rebuildGauges() {
        gauges.removeAll()
        let width = TouchBarMetrics.cellWidth(for: layout.count)
        for provider in layout {
            gauge(for: provider).setWidth(width)
        }
        NSLog(
            "QuotaBar: strip shows %d cell(s) at %.0fpt (total %.0fpt of %.0fpt)",
            layout.count, width, TouchBarMetrics.totalWidth(for: layout.count), TouchBarMetrics.barWidth
        )
    }

    /// Per-provider brand palette, matching the menu bar app (5h = accent,
    /// weekly = softer tint). C=Claude, X=Codex, K=Kimi, D=DeepSeek,
    /// S=SiliconFlow, O=OpenRouter.
    private func accent(_ tag: String) -> NSColor {
        switch tag {
        case "C": return rgb(0xD9, 0x77, 0x57)   // Claude terracotta
        case "X": return rgb(0x7B, 0x83, 0xF5)   // Codex purple-blue
        case "K": return rgb(0x2E, 0x8B, 0xFF)   // Kimi blue (brightened for dark bar)
        case "D": return rgb(0x55, 0x8B, 0xFF)   // DeepSeek blue
        case "S": return rgb(0xF2, 0x72, 0x72)   // SiliconFlow red
        case "O": return rgb(0xA0, 0x7B, 0xFF)   // OpenRouter violet
        default:  return bright
        }
    }
    private func soft(_ tag: String) -> NSColor {
        switch tag {
        case "C": return rgb(0xE3, 0xA7, 0x7F)   // Claude soft
        case "X": return rgb(0xA7, 0x8B, 0xFA)   // Codex purple
        case "K": return rgb(0x7F, 0xB3, 0xFF)   // Kimi soft
        case "D": return rgb(0x9C, 0xBE, 0xFF)   // DeepSeek soft
        case "S": return rgb(0xFF, 0xB0, 0xB0)   // SiliconFlow soft
        case "O": return rgb(0xC7, 0xAE, 0xFF)   // OpenRouter soft
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
        rebuildGauges()
        let bar = NSTouchBar()
        bar.delegate = self
        var identifiers: [NSTouchBarItem.Identifier] = [closeID, .fixedSpaceLarge]
        for (index, provider) in layout.enumerated() {
            if index > 0 { identifiers.append(.fixedSpaceSmall) }
            identifiers.append(itemID(provider))
        }
        identifiers.append(contentsOf: [.flexibleSpace, resetID])
        bar.defaultItemIdentifiers = identifiers
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
        case resetID:
            let it = NSCustomTouchBarItem(identifier: id)
            resetField.font = detailFont
            resetField.lineBreakMode = .byClipping
            resetField.maximumNumberOfLines = 1
            it.view = resetField
            return it
        default:
            guard let provider = provider(for: id) else {
                NSLog("QuotaBar: no provider for item %@", id.rawValue)
                return nil
            }
            let item = gaugeItem(id, gauge(for: provider))
            NSLog("QuotaBar: built item %@", id.rawValue)
            return item
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
            let freshLayout = TouchBarLayout.load()
            DispatchQueue.main.async {
                if freshLayout != self.layout {
                    self.layout = freshLayout
                    // Items are cached per NSTouchBar, so rebuild the modal when the
                    // selection or order changed.
                    if self.modalVisible {
                        self.minimizeModal()
                        self.presentModal()
                    }
                }
                self.usage = fresh
                self.renderTray()
                if self.modalVisible { self.renderDetail() }
            }
        }
    }

    // MARK: Rendering — tray (collapsed)

    /// (tag, window) for live quota windows of the given providers.
    private func windows(of providers: [TouchBarProvider]) -> [(String, Window)] {
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
        for provider in providers where !provider.isBalance {
            add(provider.tag, usage.provider(for: provider))
        }
        return out
    }

    /// The collapsed cell follows the coding tool in front, so it looks at every
    /// quota provider rather than at the Touch Bar selection.
    private func trayCandidates() -> [TrayGlance.Candidate] {
        TouchBarProvider.allCases.compactMap { provider in
            guard !provider.isBalance else { return nil }
            let p = usage.provider(for: provider)
            guard p.ok else { return nil }
            func glance(_ window: Window?) -> TrayGlance.Window? {
                guard let window else { return nil }
                return TrayGlance.Window(usedPct: window.usedPct, stale: window.stale || p.live == false)
            }
            return TrayGlance.Candidate(tag: provider.tag, fiveH: glance(p.fiveH), weekly: glance(p.weekly))
        }
    }

    /// The expanded bar shows the selected providers, so its reset countdown only
    /// considers those.
    private func selectedWindows() -> [(String, Window)] {
        windows(of: layout)
    }

    private func renderTray() {
        let s = NSMutableAttributedString()
        switch TrayGlance.pick(
            candidates: trayCandidates(),
            foreground: foregroundTag,
            lastUsed: lastUsedTag
        ) {
        case let pick?:
            let color = pick.stale ? dim : accent(pick.tag)
            s.append(seg(pick.tag, trayFont, color))
            s.append(seg(String(Int(pick.usedPct.rounded())), trayFont, color))
        case nil:
            s.append(seg("··", trayFont, dim))
        }
        trayButton.attributedTitle = s
        let width = ceil(s.size().width) + 16
        trayButton.frame = NSRect(x: 0, y: 0, width: max(width, 40), height: 30)
    }

    // MARK: Rendering — detail (modal, full width)

    private func renderDetail() {
        for provider in layout {
            let gauge = gauge(for: provider)
            let status = usage.provider(for: provider)
            if provider.isBalance {
                feedBalance(gauge, status)
            } else {
                feed(gauge, status)
            }
        }

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

    private func feedBalance(_ gauge: ProviderGauge, _ p: Provider) {
        guard p.ok, let balance = p.balance, balance.available else {
            gauge.updateBalance(ok: false, status: balanceStatus(p), amount: "", detail: "", cached: false)
            return
        }
        let cached = p.reason == "stale" || p.live == false
        gauge.updateBalance(ok: true, status: "",
                            amount: amountText(balance),
                            detail: balanceDetail(p),
                            cached: cached)
    }

    private func soonestReset() -> Date? {
        let now = Date()
        return selectedWindows().compactMap { $0.1.resetsAt }.filter { $0 > now }.min()
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

    private func balanceStatus(_ p: Provider) -> String {
        switch p.reason {
        case "no_data": return "未配置"
        case "expired": return "登录过期"
        case "rate_limited": return "请求受限"
        case "balance_unavailable": return "余额异常"
        case "login_required": return "未登录"
        case "loading": return "…"
        default: return "获取失败"
        }
    }

    /// Compact amount for the strip: "¥45.8", "$75" — small screens have no room.
    private func amountText(_ balance: Balance) -> String {
        let symbol = balance.currency.uppercased() == "CNY" ? "¥" : "$"
        let value = balance.amount
        if abs(value) >= 100 { return symbol + String(format: "%.0f", value) }
        return symbol + String(format: "%.1f", value)
    }

    /// Trend line under the amount, when the shared layer could estimate it.
    private func balanceDetail(_ p: Provider) -> String {
        if let days = p.burnRate?.estimatedDaysLeft, days > 0 { return "≈\(days)天" }
        if p.reason == "stale" || p.live == false { return "缓存" }
        return ""
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
