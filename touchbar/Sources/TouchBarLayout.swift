import Foundation

/// Providers the Touch Bar can show.
///
/// The menu bar app writes `touchbar_providers` (provider names, array order is
/// the display order) into the shared config file; the agent re-reads it on every
/// refresh, so a change applies without restarting QuotaBar.
enum TouchBarProvider: String, CaseIterable {
    case claude
    case codex
    case kimi
    case deepseek
    case siliconflow
    case openrouter

    /// Single-letter badge used by the gauges and by the tray cell.
    var tag: String {
        switch self {
        case .claude: return "C"
        case .codex: return "X"
        case .kimi: return "K"
        case .deepseek: return "D"
        case .siliconflow: return "S"
        case .openrouter: return "O"
        }
    }

    /// Balance providers render an amount instead of two usage bars.
    var isBalance: Bool {
        switch self {
        case .claude, .codex, .kimi: return false
        case .deepseek, .siliconflow, .openrouter: return true
        }
    }
}

enum TouchBarLayout {
    static let configKey = "touchbar_providers"
    /// What the agent showed before the setting existed.
    static let fallback: [TouchBarProvider] = [.claude, .codex, .kimi]

    /// Shared config file, honouring the same override the menu bar app uses.
    static func configURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment["AI_AGENT_USAGE_CONFIG"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ai-agent-usage-widget/config.json")
    }

    /// Ordered, de-duplicated selection. Falls back when the key is missing,
    /// empty, or lists nothing usable, so the bar is never left blank.
    static func providers(in json: [String: Any]?) -> [TouchBarProvider] {
        guard let raw = json?[configKey] as? [String] else { return fallback }
        var seen = Set<TouchBarProvider>()
        var ordered: [TouchBarProvider] = []
        for name in raw {
            guard let provider = TouchBarProvider(rawValue: name.lowercased().trimmingCharacters(in: .whitespaces)),
                  !seen.contains(provider) else {
                continue
            }
            seen.insert(provider)
            ordered.append(provider)
        }
        return ordered.isEmpty ? fallback : ordered
    }

    static func load(url: URL = configURL()) -> [TouchBarProvider] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallback
        }
        return providers(in: json)
    }
}
