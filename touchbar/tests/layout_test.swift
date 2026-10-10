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

print(failures == 0 ? "all layout tests passed" : "\(failures) layout test(s) failed")
exit(failures == 0 ? 0 : 1)
