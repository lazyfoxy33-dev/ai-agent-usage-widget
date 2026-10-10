import Foundation

/// Which providers the Touch Bar shows, and in which order.
///
/// Stored in the shared config as `touchbar_providers` (provider raw values), so
/// the Touch Bar agent can pick the change up on its next refresh.
enum TouchBarSelection {
    /// The three quota providers, i.e. what the Touch Bar showed before this
    /// setting existed. Never blank, so the strip always has something to draw.
    static let defaultValue: [AccountProviderID] = [.claude, .codex, .kimi]

    /// Ordered, de-duplicated selection; `defaultValue` when nothing usable is stored.
    static func normalize(_ names: [String]?) -> [AccountProviderID] {
        guard let names else { return defaultValue }
        var seen = Set<AccountProviderID>()
        var ordered: [AccountProviderID] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let id = AccountProviderID(rawValue: trimmed), !seen.contains(id) else { continue }
            seen.insert(id)
            ordered.append(id)
        }
        return ordered.isEmpty ? defaultValue : ordered
    }
}
