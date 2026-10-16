import Foundation

/// Which providers the dropdown menu lists, and in which order.
///
/// Stored in the shared config as `menu_providers` (provider raw values). The key
/// used to be `touchbar_providers`; `AppConfigStore` still reads that as a
/// fallback so an existing selection survives.
enum MenuProviderSelection {
    /// The three quota providers, i.e. what the menu showed before this setting
    /// existed. Never blank, so the list always has something to show.
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
