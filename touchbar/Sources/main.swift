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
    print("cells: \(providers.count) × \(Int(width))pt + chrome \(Int(TouchBarMetrics.chromeWidth))pt "
          + "= \(Int(TouchBarMetrics.totalWidth(for: providers.count)))pt of \(Int(TouchBarMetrics.barWidth))pt")
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
    line("Claude", u.claude)
    line("Codex", u.codex)
    line("Kimi", u.kimi)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
app.run()
