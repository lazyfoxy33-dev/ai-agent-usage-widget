import SwiftUI
import AppKit

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

    var providerKind: ProviderKind {
        switch self {
        case .claude: return .claude
        case .codex: return .codex
        case .kimi: return .kimi
        case .deepseek: return .deepseek
        case .siliconflow: return .siliconflow
        case .openrouter: return .openrouter
        }
    }

    var apiKeyID: APIKeyProviderID? {
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

extension APIKeyProviderID {
    var name: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .siliconflow: return "SiliconFlow"
        case .openrouter: return "OpenRouter"
        }
    }
}

@MainActor
final class AccountSettingsViewModel: ObservableObject {
    @Published private(set) var model = AccountSettingsModel()
    @Published var editingProvider: APIKeyProviderID?
    @Published var keyInput = ""
    @Published private(set) var isTesting = false
    @Published private(set) var saveErrorText: String?
    @Published private(set) var saveStatusText: String?

    private let apiKeyStore: APIKeyStore
    private let configStore: AppConfigStore
    private let usageStore: UsageStore

    init(
        apiKeyStore: APIKeyStore = APIKeyStore(),
        configStore: AppConfigStore = AppConfigStore(),
        usageStore: UsageStore = UsageStore(),
        autoload: Bool = true
    ) {
        self.apiKeyStore = apiKeyStore
        self.configStore = configStore
        self.usageStore = usageStore
        if autoload {
            reload()
        }
    }

    func reload() {
        let payload = (try? usageStore.read()).flatMap { json in
            try? UsagePayload.decode(Data(json.utf8))
        }
        let configured = Set(APIKeyProviderID.allCases.filter { provider in
            (try? apiKeyStore.read(provider)) != nil
        })
        let codexActive = configStore.readCodexActiveRefresh()

        model = AccountSettingsModel(
            payload: payload,
            configuredAPIKeys: configured,
            codexActiveRefresh: codexActive
        )
    }

    func cancelEdit() {
        editingProvider = nil
        saveErrorText = nil
    }

    func beginEdit(_ provider: APIKeyProviderID) {
        keyInput = ""
        saveErrorText = nil
        saveStatusText = nil
        editingProvider = provider
    }

    @discardableResult
    func saveKey() -> Bool {
        guard let provider = editingProvider else { return false }
        let trimmedKey = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            saveErrorText = "请输入 API Key"
            return false
        }

        do {
            try apiKeyStore.save(trimmedKey, for: provider)
            keyInput = ""
            editingProvider = nil
            saveErrorText = nil
            saveStatusText = "\(provider.name) API Key 已保存"
            reload()
            return true
        } catch {
            saveErrorText = "保存失败：\(Self.errorDescription(error))"
            return false
        }
    }

    func deleteKey(_ provider: APIKeyProviderID) {
        do {
            try apiKeyStore.delete(provider)
            saveErrorText = nil
            saveStatusText = "\(provider.name) API Key 已移除"
            reload()
        } catch {
            saveErrorText = "移除失败：\(Self.errorDescription(error))"
        }
    }

    func testProviders() {
        isTesting = true
        let apiKeyStore = self.apiKeyStore
        Task.detached { [weak self] in
            do {
                let keys = (try? QuotaWidgetModel.apiKeys(from: apiKeyStore)) ?? [:]
                let json = try UsageFetcher.fetch(apiKeys: keys, providerScope: .apiKeyOnly)
                await MainActor.run {
                    let merged = UsageFetcher.preservingLocalAgentProviders(
                        existing: try? self?.usageStore.read(),
                        in: json
                    )
                    try? self?.usageStore.write(merged)
                    self?.reload()
                    self?.isTesting = false
                }
            } catch {
                await MainActor.run {
                    self?.reload()
                    self?.isTesting = false
                }
            }
        }
    }

    func toggleCodexProbe() {
        let newValue = !model.codexActiveRefresh
        try? configStore.writeCodexActiveRefresh(enabled: newValue)
        reload()
    }

    private static func errorDescription(_ error: Error) -> String {
        if let described = error as? CustomStringConvertible {
            return described.description
        }
        return error.localizedDescription
    }

    func openLoginHelp(for id: AccountProviderID) {
        let urlString: String
        switch id {
        case .claude: urlString = "https://claude.ai/settings"
        case .kimi: urlString = "https://kimi.moonshot.cn/"
        case .codex: urlString = "https://platform.openai.com/"
        default: return
        }
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
