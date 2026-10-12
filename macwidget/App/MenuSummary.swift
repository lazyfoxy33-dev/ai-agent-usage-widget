import Foundation

/// The provider lines in the status-bar menu.
///
/// The order comes from the Touch Bar's own configuration (`touchbar_providers`),
/// so both frontends list the same providers in the same sequence — the menu is
/// a glance at exactly what the strip shows.
enum MenuSummary {
    struct Line: Identifiable, Equatable {
        let id: String
        let title: String
    }

    static func lines(from payload: UsagePayload?, order: [AccountProviderID]) -> [Line] {
        order.map { id in
            Line(id: id.rawValue, title: title(for: id, payload: payload))
        }
    }

    static func title(for id: AccountProviderID, payload: UsagePayload?) -> String {
        guard let payload else {
            return "\(id.name) · \(waitingText)"
        }
        return "\(id.name) · \(detail(for: id, provider: provider(for: id, in: payload)))"
    }

    static func provider(for id: AccountProviderID, in payload: UsagePayload) -> UsageProvider {
        switch id {
        case .claude: return payload.claude
        case .codex: return payload.codex
        case .kimi: return payload.kimi
        case .deepseek: return payload.deepseek
        case .siliconflow: return payload.siliconflow
        case .openrouter: return payload.openrouter
        }
    }

    /// Remaining quota (the app reports used %, so invert it), a balance amount, or
    /// the reason the provider has nothing to show.
    static func detail(for id: AccountProviderID, provider: UsageProvider) -> String {
        if id.kind == .apiKey {
            return balanceDetail(for: id, provider: provider)
        }
        guard provider.ok else {
            return ProviderPresentation.message(for: id.providerKind, provider: provider)
        }
        var parts: [String] = []
        if let window = provider.fiveH { parts.append("5H 剩 \(remaining(window))%") }
        if let window = provider.weekly { parts.append("周 剩 \(remaining(window))%") }
        guard !parts.isEmpty else {
            return ProviderPresentation.message(for: id.providerKind, provider: provider)
        }
        if provider.isStale { parts.append(ProviderPresentation.cachedMessage()) }
        return parts.joined(separator: " · ")
    }

    private static func balanceDetail(for id: AccountProviderID, provider: UsageProvider) -> String {
        guard provider.ok, let balance = provider.balance else {
            return ProviderPresentation.message(for: id.providerKind, provider: provider)
        }
        var parts = [ProviderPresentation.balanceAmount(balance)]
        if provider.isStale {
            parts.append(ProviderPresentation.cachedBalanceMessage())
        } else if let burnRate = provider.burnRate,
                  burnRate.confidence != "none",
                  let days = burnRate.estimatedDaysLeft,
                  days > 0 {
            parts.append(ProviderPresentation.balanceTrend(burnRate))
        }
        return parts.joined(separator: " · ")
    }

    /// Remaining share of a usage window.
    static func remaining(_ window: UsageWindow) -> Int {
        let value = 100 - window.percentage
        return max(0, min(100, Int(value.rounded())))
    }

    static var waitingText: String {
        Locale.current.language.languageCode?.identifier.hasPrefix("en") == true
            ? "waiting for refresh"
            : "等待刷新"
    }
}
