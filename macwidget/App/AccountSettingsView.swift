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
    /// Credential stored by this app in the macOS Keychain.
    let keychainCredential: Bool
    /// Credential read from dsh's own config (`~/.dsh/.credentials.yaml`).
    let externalCredential: Bool
}

struct AccountSettingsModel: Equatable {
    let payload: UsagePayload?
    let configuredAPIKeys: Set<APIKeyProviderID>
    let codexActiveRefresh: Bool
    let siliconFlowConsoleConfigured: Bool
    /// Providers whose key is not in our Keychain but is available from dsh.
    let externalCredentials: Set<APIKeyProviderID>

    init(
        payload: UsagePayload? = nil,
        configuredAPIKeys: Set<APIKeyProviderID> = [],
        codexActiveRefresh: Bool = false,
        siliconFlowConsoleConfigured: Bool = false,
        externalCredentials: Set<APIKeyProviderID> = []
    ) {
        self.payload = payload
        self.configuredAPIKeys = configuredAPIKeys
        self.codexActiveRefresh = codexActiveRefresh
        self.siliconFlowConsoleConfigured = siliconFlowConsoleConfigured
        self.externalCredentials = externalCredentials
    }

    var rows: [AccountRowState] {
        AccountProviderID.allCases.map { row(for: $0) }
    }

    private func provider(for id: AccountProviderID) -> UsageProvider? {
        guard let payload else { return nil }
        let provider: UsageProvider
        switch id {
        case .claude: provider = payload.claude
        case .codex: provider = payload.codex
        case .kimi: provider = payload.kimi
        case .deepseek: provider = payload.deepseek
        case .siliconflow: provider = payload.siliconflow
        case .openrouter: provider = payload.openrouter
        }
        return normalizedProvider(provider, for: id)
    }

    private func normalizedProvider(_ provider: UsageProvider, for id: AccountProviderID) -> UsageProvider {
        guard id == .siliconflow,
              provider.source == "console_session",
              let balance = provider.balance,
              balance.amount >= 1_000_000_000
        else {
            return provider
        }
        return UsageProvider(
            ok: provider.ok,
            reason: provider.reason,
            kind: provider.kind,
            source: provider.source,
            live: provider.live,
            fetchedAt: provider.fetchedAt,
            asOf: provider.asOf,
            fiveH: provider.fiveH,
            weekly: provider.weekly,
            balance: BalanceInfo(
                amount: balance.amount / 1_000_000_000_000,
                currency: balance.currency,
                available: balance.available,
                label: balance.label
            ),
            burnRate: provider.burnRate
        )
    }

    private func row(for id: AccountProviderID) -> AccountRowState {
        let provider = provider(for: id)
        let kind = id.kind
        let keychainCredential = keychainCredential(id: id)
        let externalCredential = externalCredential(id: id)
        let configured = isConfigured(
            id: id,
            provider: provider,
            credentialAvailable: keychainCredential || externalCredential
        )
        let statusText = statusText(for: id, provider: provider, configured: configured)
        let detailText = detailText(for: id, externalCredential: externalCredential)
        let balanceSummary = balanceSummary(for: id, provider: provider, configured: configured)

        return AccountRowState(
            id: id,
            name: id.name,
            kind: kind,
            configured: configured,
            statusText: statusText,
            detailText: detailText,
            balanceSummary: balanceSummary,
            keychainCredential: keychainCredential,
            externalCredential: externalCredential
        )
    }

    private func keychainCredential(id: AccountProviderID) -> Bool {
        guard let apiKeyID = id.apiKeyID else { return false }
        return configuredAPIKeys.contains(apiKeyID)
    }

    private func externalCredential(id: AccountProviderID) -> Bool {
        guard let apiKeyID = id.apiKeyID, !configuredAPIKeys.contains(apiKeyID) else { return false }
        return externalCredentials.contains(apiKeyID)
    }

    private func isConfigured(
        id: AccountProviderID,
        provider: UsageProvider?,
        credentialAvailable: Bool
    ) -> Bool {
        switch id {
        case .claude, .kimi:
            return provider?.ok == true
        case .codex:
            return codexActiveRefresh
        case .deepseek, .openrouter:
            return credentialAvailable
        case .siliconflow:
            return siliconFlowConsoleConfigured
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
            if provider.reason == nil {
                // Credential is present (Keychain or dsh) but nothing was fetched yet.
                return "等待首次刷新"
            }
            return ProviderPresentation.message(for: id.providerKind, provider: provider)
        }
    }

    private func detailText(for id: AccountProviderID, externalCredential: Bool) -> String? {
        if id == .siliconflow { return "控制台登录" }
        return externalCredential ? "dsh" : nil
    }

    private func balanceSummary(
        for id: AccountProviderID,
        provider: UsageProvider?,
        configured: Bool
    ) -> String? {
        guard id.kind == .apiKey, configured,
              let provider, provider.ok, provider.balance != nil else {
            return nil
        }
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
    @Published private(set) var touchBarProviders: [AccountProviderID] = TouchBarSelection.defaultValue
    @Published private(set) var saveStatusText: String?

    private let apiKeyStore: APIKeyStore
    private let siliconFlowConsoleStore: SiliconFlowConsoleSessionStore
    private let configStore: AppConfigStore
    private let usageStore: UsageStore

    init(
        apiKeyStore: APIKeyStore = APIKeyStore(),
        siliconFlowConsoleStore: SiliconFlowConsoleSessionStore = SiliconFlowConsoleSessionStore(),
        configStore: AppConfigStore = AppConfigStore(),
        usageStore: UsageStore = UsageStore(),
        autoload: Bool = true
    ) {
        self.apiKeyStore = apiKeyStore
        self.siliconFlowConsoleStore = siliconFlowConsoleStore
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
        let configuredAPIKeys = (try? apiKeyStore.readAll()) ?? [:]
        let configured = Set(configuredAPIKeys.keys)
        let codexActive = configStore.readCodexActiveRefresh()
        let consoleSession = try? siliconFlowConsoleStore.readSession()
        let external = Set(DSHCredentials.load().keys)

        model = AccountSettingsModel(
            payload: payload,
            configuredAPIKeys: configured,
            codexActiveRefresh: codexActive,
            siliconFlowConsoleConfigured: consoleSession?.isConfigured == true,
            externalCredentials: external
        )
        touchBarProviders = TouchBarSelection.normalize(configStore.readTouchBarProviders())
    }

    /// Providers that are not on the Touch Bar yet.
    var hiddenTouchBarProviders: [AccountProviderID] {
        AccountProviderID.allCases.filter { !touchBarProviders.contains($0) }
    }

    func moveTouchBarProvider(_ id: AccountProviderID, by offset: Int) {
        guard let index = touchBarProviders.firstIndex(of: id) else { return }
        let target = index + offset
        guard touchBarProviders.indices.contains(target) else { return }
        touchBarProviders.swapAt(index, target)
        persistTouchBarProviders()
    }

    func setTouchBarProvider(_ id: AccountProviderID, enabled: Bool) {
        if enabled {
            guard !touchBarProviders.contains(id) else { return }
            touchBarProviders.append(id)
        } else {
            guard touchBarProviders.count > 1 else {
                saveErrorText = "Touch Bar 至少保留一个 provider"
                return
            }
            touchBarProviders.removeAll { $0 == id }
        }
        persistTouchBarProviders()
    }

    private func persistTouchBarProviders() {
        do {
            try configStore.writeTouchBarProviders(touchBarProviders.map(\.rawValue))
            saveErrorText = nil
        } catch {
            saveErrorText = "保存 Touch Bar 设置失败：\(Self.errorDescription(error))"
        }
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

    @discardableResult
    func saveOpenRouterKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveErrorText = "OpenRouter 未返回有效密钥"
            return false
        }
        do {
            try apiKeyStore.save(trimmed, for: .openrouter)
            saveErrorText = nil
            saveStatusText = "OpenRouter 登录成功，密钥已存入钥匙串"
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

    func saveSiliconFlowConsoleSession(cookieHeader: String, subjectID: String) -> Bool {
        let trimmed = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveErrorText = "未找到 SiliconFlow 登录会话"
            return false
        }
        let trimmedSubjectID = subjectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard StoredSiliconFlowConsoleSession.isValidSubjectID(trimmedSubjectID) else {
            saveErrorText = "未找到 SiliconFlow 账户标识"
            return false
        }
        do {
            try siliconFlowConsoleStore.saveCookieHeader(trimmed)
            try siliconFlowConsoleStore.saveSubjectID(trimmedSubjectID)
            saveErrorText = nil
            saveStatusText = "SiliconFlow Console Session 已保存"
            reload()
            return true
        } catch {
            saveErrorText = "保存失败：\(Self.errorDescription(error))"
            return false
        }
    }

    func deleteSiliconFlowConsoleSession() {
        do {
            try siliconFlowConsoleStore.deleteCookieHeader()
            try siliconFlowConsoleStore.deleteSubjectID()
            saveErrorText = nil
            saveStatusText = "SiliconFlow Console Session 已移除"
            reload()
        } catch {
            saveErrorText = "移除失败：\(Self.errorDescription(error))"
        }
    }

    func testProviders() {
        isTesting = true
        let apiKeyStore = self.apiKeyStore
        let siliconFlowConsoleStore = self.siliconFlowConsoleStore
        Task.detached { [weak self] in
            do {
                let keys = UsageFetcher.mergingExternalCredentials(
                    keychain: (try? QuotaWidgetModel.apiKeys(from: apiKeyStore)) ?? [:]
                )
                var json = try UsageFetcher.fetch(apiKeys: keys, providerScope: .apiKeyOnly)
                let consoleSession = try? siliconFlowConsoleStore.readSession()
                let consoleProvider = await QuotaWidgetModel.siliconFlowConsoleProvider(
                    from: consoleSession
                )
                json = try UsageFetcher.replacingSiliconFlowProvider(
                    in: json,
                    consoleProvider: consoleProvider
                )
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
