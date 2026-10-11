import Foundation

/// Maps the frontmost application to the provider the collapsed cell should show.
///
/// This is why "the tool in front" beats "the most recently used one": running
/// DeepSeek Harness (dsh) has to show DeepSeek, not whichever coding tool
/// happened to be focused before it.
enum FrontmostTool {
    /// Substring matches, checked in order against "<bundle id> <app name>".
    private static let rules: [(needle: String, tag: String)] = [
        ("deepseek", "D"),
        ("dsh", "D"),
        ("claude", "C"),
        ("anthropic", "C"),
        ("kimi", "K"),
        ("moonshot", "K"),
        ("codex", "X"),
        ("openai", "X"),
        ("chatgpt", "X"),
    ]

    static func tag(bundleID: String, name: String) -> String? {
        let haystack = (bundleID + " " + name).lowercased()
        return rules.first { haystack.contains($0.needle) }?.tag
    }
}
