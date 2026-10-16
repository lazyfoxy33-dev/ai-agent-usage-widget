import Foundation

/// One provider's line in the status-bar panel.
struct MenuProviderRow: Identifiable, Equatable {
    enum Metric: Equatable {
        /// Remaining share of each quota window, and whether the figures are cached.
        case quota(fiveH: Int?, weekly: Int?, cached: Bool)
        /// Balance amount plus the days-left trend, when one is known.
        case balance(amount: String, trend: String?, daysLeft: Int?, cached: Bool)
        /// Nothing to show: the reason, already localised.
        case unavailable(String)
    }

    let id: AccountProviderID
    let name: String
    let metric: Metric

    var isCached: Bool {
        switch metric {
        case .quota(_, _, let cached): return cached
        case .balance(_, _, _, let cached): return cached
        case .unavailable: return false
        }
    }

    var isAvailable: Bool {
        if case .unavailable = metric { return false }
        return true
    }
}

/// Turns the shared payload into the rows the status-bar panel shows.
///
/// The order comes from the 「菜单显示」 setting (`menu_providers`).
enum MenuSummary {
    static func rows(from payload: UsagePayload?, order: [AccountProviderID]) -> [MenuProviderRow] {
        order.map { id in
            MenuProviderRow(
                id: id,
                name: id.name,
                metric: payload.map { metric(for: id, provider: provider(for: id, in: $0)) }
                    ?? .unavailable(waitingText)
            )
        }
    }

    /// How many providers currently report usable figures.
    static func connectedCount(from payload: UsagePayload?) -> Int {
        guard let payload else { return 0 }
        return AccountProviderID.allCases.filter { id in
            let figures = provider(for: id, in: payload)
            return figures.ok && (figures.balance != nil || figures.fiveH != nil || figures.weekly != nil)
        }.count
    }

    static func metric(for id: AccountProviderID, provider: UsageProvider) -> MenuProviderRow.Metric {
        if id.kind == .apiKey {
            guard provider.ok, let balance = provider.balance else {
                return .unavailable(ProviderPresentation.message(for: id.providerKind, provider: provider))
            }
            let burnRate = provider.burnRate
            let usable = ProviderPresentation.isTrendUsable(burnRate)
            let trend: String? = provider.isStale
                ? ProviderPresentation.cachedBalanceMessage()
                : ProviderPresentation.balanceTrendLine(burnRate, currency: balance.currency)
            return .balance(
                amount: ProviderPresentation.balanceAmount(balance),
                trend: trend,
                daysLeft: usable && !provider.isStale ? burnRate?.estimatedDaysLeft : nil,
                cached: provider.isStale
            )
        }

        guard provider.ok, provider.fiveH != nil || provider.weekly != nil else {
            return .unavailable(ProviderPresentation.message(for: id.providerKind, provider: provider))
        }
        return .quota(
            fiveH: provider.fiveH.map(remaining),
            weekly: provider.weekly.map(remaining),
            cached: provider.isStale
        )
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

    /// Remaining share of a usage window; the contract reports used %.
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
