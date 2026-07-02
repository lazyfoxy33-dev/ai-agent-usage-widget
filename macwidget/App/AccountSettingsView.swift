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

    private let apiKeyStore: APIKeyStore
    private let configStore: AppConfigStore
    private let usageStore: UsageStore

    init(
        apiKeyStore: APIKeyStore = APIKeyStore(),
        configStore: AppConfigStore = AppConfigStore(),
        usageStore: UsageStore = UsageStore()
    ) {
        self.apiKeyStore = apiKeyStore
        self.configStore = configStore
        self.usageStore = usageStore
        reload()
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

    func beginEdit(_ provider: APIKeyProviderID) {
        keyInput = ""
        editingProvider = provider
    }

    func saveKey() {
        guard let provider = editingProvider, !keyInput.isEmpty else { return }
        try? apiKeyStore.save(keyInput, for: provider)
        editingProvider = nil
        reload()
    }

    func deleteKey(_ provider: APIKeyProviderID) {
        try? apiKeyStore.delete(provider)
        reload()
    }

    func testProviders() {
        isTesting = true
        let apiKeyStore = self.apiKeyStore
        Task.detached { [weak self] in
            do {
                let keys = (try? QuotaWidgetModel.apiKeys(from: apiKeyStore)) ?? [:]
                let json = try UsageFetcher.fetch(apiKeys: keys)
                await MainActor.run {
                    try? self?.usageStore.write(json)
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

struct AccountSettingsView: View {
    @StateObject private var viewModel: AccountSettingsViewModel

    init(viewModel: AccountSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            Section("Local agent accounts") {
                ForEach(viewModel.model.rows.filter { $0.kind == .localAgent }) { row in
                    AccountRowView(
                        row: row,
                        onToggleProbe: { viewModel.toggleCodexProbe() },
                        onLoginHelp: { viewModel.openLoginHelp(for: row.id) }
                    )
                }
            }

            Section("API balance accounts") {
                ForEach(viewModel.model.rows.filter { $0.kind == .apiKey }) { row in
                    AccountRowView(
                        row: row,
                        onAddKey: { row.id.apiKeyID.map(viewModel.beginEdit) },
                        onRemoveKey: { row.id.apiKeyID.map(viewModel.deleteKey) },
                        onTest: { viewModel.testProviders() }
                    )
                }
            }

        }
        .frame(minWidth: 360, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Test All") { viewModel.testProviders() }
                    .disabled(viewModel.isTesting)
            }
        }
        .sheet(item: $viewModel.editingProvider) { provider in
            APIKeySheet(
                provider: provider,
                keyInput: $viewModel.keyInput,
                onSave: viewModel.saveKey
            )
        }
        .onAppear { viewModel.reload() }
    }
}

struct AccountRowView: View {
    let row: AccountRowState
    var onAddKey: (() -> Void)?
    var onRemoveKey: (() -> Void)?
    var onTest: (() -> Void)?
    var onToggleProbe: (() -> Void)?
    var onLoginHelp: (() -> Void)?

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

            rowActions

            StatusIndicator(configured: row.configured)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var rowActions: some View {
        switch row.id.kind {
        case .localAgent:
            if row.id == .codex {
                Button(row.configured ? "Disable Probe" : "Enable Probe") {
                    onToggleProbe?()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Open") {
                    onLoginHelp?()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .apiKey:
            if row.configured {
                HStack(spacing: 4) {
                    Button("Test") { onTest?() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Remove") { onRemoveKey?() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else {
                Button("Add Key") { onAddKey?() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }
}

struct StatusIndicator: View {
    let configured: Bool

    var body: some View {
        Image(systemName: configured ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundStyle(configured ? .green : .orange)
    }
}

struct APIKeySheet: View {
    let provider: APIKeyProviderID
    @Binding var keyInput: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(provider.name) API Key")
                .font(.headline)
            SecureField("API Key", text: $keyInput)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave()
                    dismiss()
                }
                .disabled(keyInput.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 320)
    }
}

#Preview {
    AccountSettingsView(
        viewModel: AccountSettingsViewModel(
            apiKeyStore: APIKeyStore(backend: InMemoryCredentialBackend()),
            configStore: AppConfigStore(
                baseDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            usageStore: UsageStore(containerURLProvider: {
                FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            })
        )
    )
}
