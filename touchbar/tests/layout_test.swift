// Layout parsing tests for the Touch Bar agent.
//
// Compiled with the layout source by `touchbar/tests/run-layout-tests.sh`:
//
//     swiftc -o /tmp/quota-layout-tests \
//         Sources/TouchBarLayout.swift tests/layout_test.swift && /tmp/quota-layout-tests
//
// The agent has no Xcode test bundle, so this checks the parser that decides
// what the strip shows.
import Foundation

var failures = 0

func expect(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok   \(message)")
    } else {
        failures += 1
        print("  FAIL \(message)")
    }
}

func providers(_ json: [String: Any]?) -> [TouchBarProvider] {
    TouchBarLayout.providers(in: json)
}

print("TouchBarLayout")

expect(
    providers(nil) == [.claude, .codex, .kimi],
    "missing key keeps the historical default"
)
expect(
    providers(["touchbar_providers": []]) == [.claude, .codex, .kimi],
    "empty list keeps the historical default"
)
expect(
    providers(["touchbar_providers": ["nope"]]) == [.claude, .codex, .kimi],
    "unknown names fall back instead of blanking the strip"
)
expect(
    providers(["touchbar_providers": ["openrouter", "kimi", "KIMI", "claude"]])
        == [.openrouter, .kimi, .claude],
    "order is preserved and duplicates are dropped"
)
expect(
    providers(["touchbar_providers": [" kimi ", "DeepSeek"]]) == [.kimi, .deepseek],
    "names are trimmed and case-insensitive"
)
expect(
    providers(["touchbar_providers": ["claude", "codex", "kimi", "deepseek", "siliconflow", "openrouter"]])
        == [.claude, .codex, .kimi, .deepseek, .siliconflow, .openrouter],
    "all six providers can be selected together"
)
expect(
    TouchBarProvider.deepseek.isBalance && !TouchBarProvider.kimi.isBalance,
    "balance providers are distinguishable from quota providers"
)
expect(
    TouchBarProvider.allCases.map(\.tag).joined() == "CXKDSO",
    "every provider has a unique badge letter"
)

// Reading the shared config file, including the environment override.
let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("quotabar-layout-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let config = root.appendingPathComponent("config.json")

try? #"{"touchbar_providers":["siliconflow","claude"]}"#
    .write(to: config, atomically: true, encoding: .utf8)
expect(
    TouchBarLayout.load(url: config) == [.siliconflow, .claude],
    "reads the configured order from disk"
)

try? #"{"codex_active_refresh":true}"#
    .write(to: config, atomically: true, encoding: .utf8)
expect(
    TouchBarLayout.load(url: config) == [.claude, .codex, .kimi],
    "a config without the key keeps the default"
)

expect(
    TouchBarLayout.configURL(environment: ["AI_AGENT_USAGE_CONFIG": "/tmp/x/config.json"]).path
        == "/tmp/x/config.json",
    "honours the shared config override"
)

// MARK: collapsed cell (TrayGlance)

print("TrayGlance")

func candidate(_ tag: String, _ fiveH: Double?, _ weekly: Double? = nil, stale: Bool = false) -> TrayGlance.Candidate {
    func window(_ pct: Double?) -> TrayGlance.Window? {
        guard let pct else { return nil }
        return TrayGlance.Window(usedPct: pct, stale: stale)
    }
    return TrayGlance.Candidate(tag: tag, fiveH: window(fiveH), weekly: window(weekly))
}

let claude = candidate("C", 30)
let codex = candidate("X", 80)
let kimi = candidate("K", 95)

expect(
    TrayGlance.pick(candidates: [claude, codex, kimi], foreground: "C", lastUsed: "K")
        == TrayGlance.Pick(tag: "C", usedPct: 30, stale: false),
    "the frontmost coding tool wins even when another provider is more drained"
)
expect(
    TrayGlance.pick(candidates: [claude, codex, kimi], foreground: nil, lastUsed: "X")
        == TrayGlance.Pick(tag: "X", usedPct: 80, stale: false),
    "without a frontmost tool the most recently used one is used"
)
expect(
    TrayGlance.pick(candidates: [candidate("C", nil), codex, kimi], foreground: "C", lastUsed: nil)
        == TrayGlance.Pick(tag: "K", usedPct: 95, stale: false),
    "a frontmost tool without data falls back to the most-drained one"
)
expect(
    TrayGlance.pick(candidates: [claude], foreground: nil, lastUsed: nil)
        == TrayGlance.Pick(tag: "C", usedPct: 30, stale: false),
    "with no frontmost context the only provider is shown"
)
expect(
    TrayGlance.pick(candidates: [], foreground: "C", lastUsed: "C") == nil,
    "no candidates yields no cell content"
)
expect(
    TrayGlance.mostDrained([candidate("C", 95, stale: true), candidate("X", 80)])
        == TrayGlance.Pick(tag: "X", usedPct: 80, stale: false),
    "a fresh figure beats a staler, higher one"
)
expect(
    TrayGlance.pick(candidates: [candidate("K", 100, nil, stale: true)], foreground: "K", lastUsed: nil)
        == TrayGlance.Pick(tag: "K", usedPct: 100, stale: true),
    "stale data is still shown, flagged as stale"
)
expect(
    TrayGlance.tightest(in: [candidate("C", 10, 70)], tag: "C")
        == TrayGlance.Pick(tag: "C", usedPct: 70, stale: false),
    "the more-drained window of a provider is used"
)
expect(
    TrayGlance.tightest(in: [candidate("C", 10)], tag: "X") == nil,
    "an unknown tag has no window"
)

// MARK: strip widths (TouchBarMetrics)

print("TouchBarMetrics")

expect(TouchBarMetrics.cellWidth(for: 3) == 170, "three providers keep the original 170pt card")
expect(TouchBarMetrics.cellWidth(for: 1) == 170, "a single provider is not stretched beyond the card")
expect(
    TouchBarMetrics.cellWidth(for: 6) >= TouchBarMetrics.minCellWidth,
    "six providers stay above the legible minimum"
)
expect(
    (1...6).allSatisfy { TouchBarMetrics.cellsWidth(for: $0) <= TouchBarMetrics.cellBudget },
    "every supported selection fits the measured cell budget"
)
expect(
    TouchBarMetrics.cellWidth(for: 5) < TouchBarMetrics.cellWidth(for: 4),
    "more providers means narrower cells"
)
// Measured on hardware: five cells survive at 110pt but not at 120pt, so the
// default for five must sit at or below that.
expect(
    TouchBarMetrics.cellWidth(for: 5) <= 110,
    "five cells are sized for a strip that drops them above 110pt"
)
expect(
    TouchBarMetrics.cellWidth(for: 5) < TouchBarMetrics.compactThreshold,
    "five cells switch to the compact layout"
)
expect(
    TouchBarMetrics.cellWidth(for: 4) <= 134,
    "four cells stay within the measured budget"
)

// MARK: usage source (app mirror vs core layer)

print("UsageSource")

expect(
    UsageSource.mirrorURL(environment: [:]).path.hasSuffix(".config/ai-agent-usage-widget/usage.json"),
    "the mirror sits beside the shared config file"
)
expect(
    UsageSource.mirrorURL(environment: ["AI_AGENT_USAGE_CONFIG": "/tmp/x/config.json"]).path == "/tmp/x/usage.json",
    "the mirror honours the shared config override"
)
let now = Date()
expect(
    UsageSource.isFresh(modifiedAt: now.addingTimeInterval(-60), now: now),
    "a minute-old mirror is fresh"
)
expect(
    !UsageSource.isFresh(modifiedAt: now.addingTimeInterval(-3600), now: now),
    "an hour-old mirror is stale and the core layer is used instead"
)
expect(
    !UsageSource.isFresh(modifiedAt: now.addingTimeInterval(600), now: now),
    "a far-future timestamp is not trusted"
)
let payload = #"{"siliconflow":{"ok":true,"kind":"balance","source":"console_session","balance":{"amount":42.5,"currency":"CNY","available":true,"label":"Console Balance"}},"deepseek":{"ok":false,"reason":"no_data"}}"#
if let parsed = UsageSource.usage(from: Data(payload.utf8)) {
    expect(
        parsed.siliconflow.ok && parsed.siliconflow.balance?.amount == 42.5,
        "parses a balance provider out of the shared contract"
    )
    expect(parsed.siliconflow.source == "console_session", "keeps the credential source")
    expect(parsed.deepseek.reason == "no_data", "keeps a failure reason")
} else {
    expect(false, "parses the shared contract")
}

print(failures == 0 ? "all layout tests passed" : "\(failures) layout test(s) failed")
exit(failures == 0 ? 0 : 1)
