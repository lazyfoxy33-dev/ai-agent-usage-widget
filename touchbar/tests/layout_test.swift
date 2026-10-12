// Layout parsing tests for the Touch Bar agent.
//
// Compiled with the layout source by `touchbar/tests/run-layout-tests.sh`:
//
//     swiftc -o /tmp/quota-layout-tests \
//         Sources/TouchBarLayout.swift tests/layout_test.swift && /tmp/quota-layout-tests
//
// The agent has no Xcode test bundle, so this checks the parser that decides
// what the strip shows.
import AppKit
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

// MARK: stale mirror merge + real mirror reads

let coreJSON: [String: Any] = [
    "claude": ["ok": true],
    "siliconflow": ["ok": false, "reason": "login_required", "source": "console_session"],
    "deepseek": ["ok": false, "reason": "no_data"],
]
let mirrorJSON: [String: Any] = [
    "siliconflow": [
        "ok": true, "kind": "balance", "source": "console_session",
        "balance": ["amount": 42.5, "currency": "CNY", "available": true],
    ],
    "deepseek": ["ok": false, "reason": "no_data"],
]
func parse(_ dict: [String: Any]) -> Usage? {
    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
    return UsageSource.usage(from: data)
}
if let core = parse(coreJSON), let mirror = parse(mirrorJSON) {
    let merged = UsageSource.merging(core: core, mirror: mirror)
    expect(
        merged.siliconflow.ok && merged.siliconflow.balance?.amount == 42.5,
        "a stale mirror still supplies the real SiliconFlow balance"
    )
    expect(
        merged.siliconflow.reason == "stale" && merged.siliconflow.live == false,
        "a balance kept from a stale mirror is marked cached"
    )
    expect(merged.siliconflow.source == "console_session", "the credential source survives the merge")
    expect(merged.origin == "core+app", "the merge reports where the data came from")
    expect(merged.claude.ok, "quota providers come from the fresh core read")
    expect(!merged.deepseek.ok, "a mirror without a usable balance does not clobber the core result")
} else {
    expect(false, "parses the merge fixtures")
}

// A real mirror file, read through the shared config override.
let mirrorRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("quotabar-mirror-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: mirrorRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: mirrorRoot) }
let mirrorConfig = mirrorRoot.appendingPathComponent("config.json")
let mirrorFile = mirrorRoot.appendingPathComponent("usage.json")
setenv("AI_AGENT_USAGE_CONFIG", mirrorConfig.path, 1)
try? JSONSerialization.data(withJSONObject: mirrorJSON).write(to: mirrorFile)
expect(UsageSource.mirrorURL().path == mirrorFile.path, "the mirror is read from beside the config override")
if let (snapshot, _) = UsageSource.readMirrorSnapshot() {
    expect(snapshot.siliconflow.balance?.amount == 42.5, "a mirror written to disk is parsed")
} else {
    expect(false, "reads the mirror written to disk")
}
expect(
    UsageSource.readMirror(now: Date().addingTimeInterval(3600)) == nil,
    "the same mirror is rejected once it is stale"
)
unsetenv("AI_AGENT_USAGE_CONFIG")

// MARK: brand icons

print("icons")

expect(
    TouchBarProvider.allCases.map(\.iconAssetName) == [
        "claude-app", "codex-app", "kimi-code", "deepseek", "siliconflow", "openrouter",
    ],
    "every provider maps to the icon the settings window uses"
)
expect(
    Set(TouchBarProvider.allCases.map(\.iconAssetName)).count == TouchBarProvider.allCases.count,
    "no two providers share an asset"
)

// MARK: frontmost tool mapping

print("FrontmostTool")

expect(FrontmostTool.tag(bundleID: "com.deepseek.dsh", name: "DeepSeek Harness") == "D",
       "DeepSeek Harness maps to DeepSeek")
expect(FrontmostTool.tag(bundleID: "", name: "DeepSeek Harness Helper") == "D",
       "helper processes map too")
expect(FrontmostTool.tag(bundleID: "com.anthropic.claudefordesktop", name: "Claude") == "C",
       "Claude maps to Claude")
expect(FrontmostTool.tag(bundleID: "com.moonshot.kimichat", name: "Kimi") == "K",
       "Kimi maps to Kimi")
expect(FrontmostTool.tag(bundleID: "com.openai.codex", name: "Codex") == "X",
       "Codex maps to Codex")
expect(FrontmostTool.tag(bundleID: "com.apple.finder", name: "Finder") == nil,
       "anything else has no provider")
expect(FrontmostTool.tag(bundleID: "com.apple.Terminal", name: "Terminal") == nil,
       "a terminal in front is not a provider")

// The collapsed cell text: the icon names the provider, so no letter is repeated.
expect(TrayGlance.label(tag: "D", figure: "¥32.6", hasIcon: true) == "¥32.6",
       "with an icon only the figure is shown")
expect(TrayGlance.label(tag: "D", figure: "¥32.6", hasIcon: false) == "D¥32.6",
       "without an icon the tag letter stays")
expect(TrayGlance.percentageLabel(tag: "X", usedPct: 5.4, hasIcon: true) == "5%",
       "percentages are rounded and suffixed")

// MARK: icon plate keying

print("ProviderIcon")

func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> [UInt8] {
    [UInt8((r * a * 255).rounded()), UInt8((g * a * 255).rounded()),
     UInt8((b * a * 255).rounded()), UInt8((a * 255).rounded())]
}
func plate(_ pixel: [UInt8], side: Int) -> [UInt8] {
    Array(repeating: pixel, count: side * side).flatMap { $0 }
}
expect(ProviderIcon.lightPlateColor(pixels: plate(rgba(1, 1, 1, 1), side: 4), side: 4) != nil,
       "a white plate is detected")
expect(ProviderIcon.lightPlateColor(pixels: plate(rgba(0, 0, 0, 0), side: 4), side: 4) == nil,
       "a transparent background is not a plate")
expect(ProviderIcon.lightPlateColor(pixels: plate(rgba(0.85, 0.47, 0.34, 1), side: 4), side: 4) == nil,
       "a coloured plate is part of the brand and is kept")

func repoImage(_ name: String) -> NSImage? {
    let path = "../macwidget/App/Resources/\(name).png"
    return NSImage(contentsOfFile: path)
}
expect(repoImage("codex-app").flatMap { ProviderIcon.keyedOut($0) } != nil,
       "the Codex asset's white plate is keyed out")
expect(repoImage("claude-app").flatMap { ProviderIcon.keyedOut($0) } == nil,
       "the Claude asset keeps its orange plate")

// MARK: balance trend wording

print("BalanceTrend")

func burn(_ window: Int?, _ days: Int?, _ confidence: String, _ reason: String? = nil) -> BurnRate {
    BurnRate(
        amountPerDay: 1,
        windowDays: window,
        estimatedDaysLeft: days,
        confidence: confidence,
        reason: reason
    )
}

expect(BalanceTrend.text(for: burn(1, 30, "medium")) == "≈30天",
       "a full day of history gives a figure")
expect(BalanceTrend.text(for: burn(0, 4, "low")) == "≈4天",
       "a young history still shows its recent average")
expect(BalanceTrend.text(for: burn(1, 30, "none", "insufficient_history")) == "样本不足",
       "the estimator asking for samples becomes a caveat")
expect(BalanceTrend.text(for: burn(1, 30, "none", "no_recent_spend")) == nil,
       "no recent spend means no line")
expect(BalanceTrend.text(for: burn(1, 0, "medium")) == "不足1天",
       "less than a day left is reported, not hidden")
expect(BalanceTrend.text(for: nil) == nil, "no burn rate means no line")

print(failures == 0 ? "all layout tests passed" : "\(failures) layout test(s) failed")
exit(failures == 0 ? 0 : 1)
