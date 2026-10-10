import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = TouchBarController()
    func applicationDidFinishLaunching(_ note: Notification) {
        controller.start()
    }
}

// Debug: `QuotaBar --layout` prints what the strip would show, then exits.
if CommandLine.arguments.contains("--layout") {
    let providers = TouchBarLayout.load()
    let width = TouchBarMetrics.cellWidth(for: providers.count)
    print("config: \(TouchBarLayout.configURL().path)")
    print("providers: \(providers.map { "\($0.rawValue)(\($0.tag))" }.joined(separator: " "))")
    print("cells: \(providers.count) × \(Int(width))pt + spacing = "
          + "\(Int(TouchBarMetrics.cellsWidth(for: providers.count)))pt of \(Int(TouchBarMetrics.cellBudget))pt budget")
    exit(0)
}

// Debug: `QuotaBar --once` fetches via the shared core layer, prints, and exits.
if CommandLine.arguments.contains("--once") {
    func line(_ name: String, _ p: Provider) {
        func w(_ win: Window?) -> String {
            guard let win = win else { return "–" }
            var s = "\(Int(win.usedPct.rounded()))% used"
            if let r = win.resetsAt {
                let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"
                s += " · resets \(f.string(from: r))"
            }
            if win.stale { s += " (stale)" }
            return s
        }
        print("\(name):")
        if !p.ok { print("  \(p.reason ?? "unavailable")"); return }
        print("  5h     \(w(p.fiveH))")
        print("  weekly \(w(p.weekly))")
    }
    let u = UsageSource.read()
    print("source: \(u.origin) (\(u.updatedAt.formatted(date: .omitted, time: .standard)))")
    line("Claude", u.claude)
    line("Codex", u.codex)
    line("Kimi", u.kimi)
    func state(_ name: String, _ p: Provider) {
        let amount = p.balance.map { _ in "有余额" } ?? "无余额"
        print("\(name): ok=\(p.ok) reason=\(p.reason ?? "-") source=\(p.source ?? "-") \(amount)")
    }
    state("DeepSeek", u.deepseek)
    state("SiliconFlow", u.siliconflow)
    state("OpenRouter", u.openrouter)
    exit(0)
}

// Debug: `QuotaBar --present-test` presents the strip, reports what macOS kept,
// then exits. Used to measure the real usable width on a given Mac.
if CommandLine.arguments.contains("--present-test") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let probe = TouchBarController()
    probe.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        probe.presentForDiagnostics()
    }
    if CommandLine.arguments.contains("--measure") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            print("measuring strip capacity with \(TouchBarLayout.load().count) cells:")
            probe.measureStrip(widths: [170, 150, 130, 120, 110, 100, 90]) {
                probe.printPresentationReport()
                exit(0)
            }
        }
    } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            probe.printPresentationReport()
            exit(0)
        }
    }
    app.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
app.run()
