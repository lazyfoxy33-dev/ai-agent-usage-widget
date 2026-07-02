import SwiftUI

enum AccountProviderID: String, CaseIterable, Identifiable {
    case claude, codex, kimi, deepseek, siliconflow, openrouter

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .kimi: return "Kimi Code"
        case .deepseek: return "DeepSeek"
        case .siliconflow: return "SiliconFlow"
        case .openrouter: return "OpenRouter"
        }
    }

    var kind: AccountKind {
        switch self {
        case .claude, .codex, .kimi:
            return .localAgent
        case .deepseek, .siliconflow, .openrouter:
            return .apiKey
        }
    }

    fileprivate var providerKind: ProviderKind {
        switch self {
        case .claude: return .claude
        case .codex: return .codex
        case .kimi: return .kimi
        case .deepseek: return .deepseek
        case .siliconflow: return .siliconflow
        case .openrouter: return .openrouter
        }
    }

    fileprivate var apiKeyID: APIKeyProviderID? {
        switch self {
        case .deepseek: return .deepseek
        case .siliconflow: return .siliconflow
        case .openrouter: return .openrouter
        default: return nil
        }
    }
}

enum AccountKind {
    case localAgent
    case apiKey
}

struct AccountRowState: Identifiable, Equatable {
    let id: AccountProviderID
    let name: String
    let kind: AccountKind
    let configured: Bool
    let statusText: String
    let detailText: String?
    let balanceSummary: String?
}

struct AccountSettingsModel: Equatable {
    let payload: UsagePayload?
    let configuredAPIKeys: Set<APIKeyProviderID>
    let codexActiveRefresh: Bool

    init(
        payload: UsagePayload? = nil,
        configuredAPIKeys: Set<APIKeyProviderID> = [],
        codexActiveRefresh: Bool = false
    ) {
        self.payload = payload
        self.configuredAPIKeys = configuredAPIKeys
        self.codexActiveRefresh = codexActiveRefresh
    }

    var rows: [AccountRowState] {
        AccountProviderID.allCases.map { row(for: $0) }
    }

    private func provider(for id: AccountProviderID) -> UsageProvider? {
        guard let payload else { return nil }
        switch id {
        case .claude: return payload.claude
        case .codex: return payload.codex
        case .kimi: return payload.kimi
        case .deepseek: return payload.deepseek
        case .siliconflow: return payload.siliconflow
        case .openrouter: return payload.openrouter
        }
    }

    private func row(for id: AccountProviderID) -> AccountRowState {
        let provider = provider(for: id)
        let kind = id.kind
        let configured = isConfigured(id: id, provider: provider)
        let statusText = statusText(for: id, provider: provider, configured: configured)
        let detailText = detailText(for: id)
        let balanceSummary = balanceSummary(for: id, provider: provider, configured: configured)

        return AccountRowState(
            id: id,
            name: id.name,
            kind: kind,
            configured: configured,
            statusText: statusText,
            detailText: detailText,
            balanceSummary: balanceSummary
        )
    }

    private func isConfigured(id: AccountProviderID, provider: UsageProvider?) -> Bool {
        switch id {
        case .claude, .kimi:
            return provider?.ok == true
        case .codex:
            return codexActiveRefresh
        case .deepseek, .siliconflow, .openrouter:
            guard let apiKeyID = id.apiKeyID else { return false }
            return configuredAPIKeys.contains(apiKeyID)
        }
    }

    private func statusText(
        for id: AccountProviderID,
        provider: UsageProvider?,
        configured: Bool
    ) -> String {
        let provider = provider ?? UsageProvider(ok: false)

        switch id.kind {
        case .localAgent:
            if provider.ok && provider.live == true {
                return activeStatusText()
            }
            return ProviderPresentation.message(for: id.providerKind, provider: provider)

        case .apiKey:
            guard configured else {
                return ProviderPresentation.message(for: id.providerKind, provider: provider)
            }
            if provider.ok && provider.live == true {
                return ProviderPresentation.balanceAmount(provider.balance)
            }
            if provider.isStale {
                return ProviderPresentation.cachedBalanceMessage()
            }
            return ProviderPresentation.message(for: id.providerKind, provider: provider)
        }
    }

    private func detailText(for id: AccountProviderID) -> String? {
        switch id.kind {
        case .localAgent: return "Local Agent"
        case .apiKey: return "API Key"
        }
    }

    private func balanceSummary(
        for id: AccountProviderID,
        provider: UsageProvider?,
        configured: Bool
    ) -> String? {
        guard id.kind == .apiKey, configured else { return nil }
        let provider = provider ?? UsageProvider(ok: false)
        let amount = ProviderPresentation.balanceAmount(provider.balance)
        let trend = ProviderPresentation.balanceTrend(provider.burnRate)
        return "\(amount) · \(trend)"
    }

    private func activeStatusText() -> String {
        let code = Locale.current.language.languageCode?.identifier ?? "zh"
        return code.hasPrefix("en") ? "Active" : "正常"
    }
}

struct AccountSettingsView: View {
    let model: AccountSettingsModel

    var body: some View {
        List {
            Section("Local agent accounts") {
                ForEach(model.rows.filter { $0.kind == .localAgent }) { row in
                    AccountRowView(row: row)
                }
            }

            Section("API balance accounts") {
                ForEach(model.rows.filter { $0.kind == .apiKey }) { row in
                    AccountRowView(row: row)
                }
            }

            Section {
                Text("API keys are stored in the macOS Keychain and are never shared with the widget extension.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 360, minHeight: 400)
    }
}

struct AccountRowView: View {
    let row: AccountRowState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.headline)
                if let detailText = row.detailText {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(row.statusText)
                    .font(.caption)
                    .foregroundStyle(row.configured ? .primary : .secondary)
            }

            Spacer()

            if let balanceSummary = row.balanceSummary {
                Text(balanceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            StatusIndicator(configured: row.configured)
        }
        .padding(.vertical, 2)
    }
}

struct StatusIndicator: View {
    let configured: Bool

    var body: some View {
        Image(systemName: configured ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundStyle(configured ? .green : .orange)
    }
}

#Preview {
    AccountSettingsView(
        model: AccountSettingsModel(
            payload: .preview,
            configuredAPIKeys: [.siliconflow],
            codexActiveRefresh: false
        )
    )
}
