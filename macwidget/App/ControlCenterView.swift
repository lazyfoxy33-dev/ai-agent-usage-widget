import SwiftUI

// Providers: Claude, Codex, Kimi Code, DeepSeek, SiliconFlow, OpenRouter

// MARK: - Navigation

enum ControlPage: String, CaseIterable, Identifiable {
    case accounts
    case refresh
    case displays
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts: return "Accounts"
        case .refresh: return "Refresh"
        case .displays: return "Displays"
        case .diagnostics: return "Diagnostics"
        }
    }

    var icon: String {
        switch self {
        case .accounts: return "person.2"
        case .refresh: return "arrow.clockwise"
        case .displays: return "display"
        case .diagnostics: return "stethoscope"
        }
    }
}

// MARK: - Main View

struct ControlCenterView: View {
    @State private var selectedPage: ControlPage = .accounts
    @ObservedObject var accountViewModel: AccountSettingsViewModel
    let displayStore: DisplayLayerStore
    let usageStore: UsageStore
    let refreshNow: () -> Void
    let displayActions: DisplayLayerActions

    var body: some View {
        HStack(spacing: 0) {
            ControlSidebar(
                selectedPage: $selectedPage,
                usageStore: usageStore,
                accountViewModel: accountViewModel
            )
            .frame(width: 220)

            Divider()

            contentView
                .frame(minWidth: 560)
        }
        .frame(minWidth: 780, minHeight: 480)
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedPage {
        case .accounts:
            AccountsPage(viewModel: accountViewModel, refreshNow: refreshNow)
        case .refresh:
            RefreshPage(refreshNow: refreshNow)
        case .displays:
            DisplaysPage(displayStore: displayStore, actions: displayActions)
        case .diagnostics:
            DiagnosticsPage(usageStore: usageStore, displayStore: displayStore)
        }
    }
}

// MARK: - Sidebar

struct ControlSidebar: View {
    @Binding var selectedPage: ControlPage
    let usageStore: UsageStore
    @ObservedObject var accountViewModel: AccountSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("QuotaWidget")
                    .font(.system(size: 16, weight: .bold))
                Text("AI Agent Usage control center")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            VStack(spacing: 2) {
                ForEach(ControlPage.allCases) { page in
                    SidebarButton(
                        page: page,
                        isSelected: selectedPage == page,
                        action: { selectedPage = page }
                    )
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            SidebarStatus(
                usageStore: usageStore,
                accountViewModel: accountViewModel
            )
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct SidebarButton: View {
    let page: ControlPage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: page.icon)
                    .frame(width: 18, height: 18)
                Text(page.title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.white.opacity(0.86) : Color.clear)
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? Color.black.opacity(0.06) : Color.clear, lineWidth: 1)
        )
        .fontWeight(isSelected ? .semibold : .regular)
    }
}

struct SidebarStatus: View {
    let usageStore: UsageStore
    @ObservedObject var accountViewModel: AccountSettingsViewModel

    var body: some View {
        let status = usageStore.status()
        let configuredCount = accountViewModel.model.rows.filter(\.configured).count

        VStack(spacing: 7) {
            StatusLine(label: "Shared state", value: status.available ? "Available" : "\(status.reason)")
            StatusLine(label: "Last refresh", value: "—")
            StatusLine(label: "Configured", value: "\(configuredCount) / 6")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(10)
        .background(Color.white.opacity(0.62))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

struct StatusLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

extension UsageStoreStatus.Reason: CustomStringConvertible {
    var description: String {
        switch self {
        case .ok: return "OK"
        case .missingContainer: return "Missing container"
        case .missingUsageFile: return "Missing usage file"
        }
    }
}

// MARK: - Accounts Page

struct AccountsPage: View {
    @ObservedObject var viewModel: AccountSettingsViewModel
    let refreshNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AccountsToolbar(refreshNow: refreshNow, onTest: { viewModel.testProviders() }, isTesting: viewModel.isTesting)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SummaryMetrics(model: viewModel.model)

                    ProviderSection(title: "Local Agents", subtitle: "Read from local authenticated tools") {
                        ForEach(viewModel.model.rows.filter { $0.kind == .localAgent }) { row in
                            ProviderRow(
                                row: row,
                                onToggleProbe: row.id == .codex ? { viewModel.toggleCodexProbe() } : nil,
                                onLoginHelp: row.id != .codex ? { viewModel.openLoginHelp(for: row.id) } : nil
                            )
                        }
                    }

                    ProviderSection(title: "API Balance", subtitle: "Keys stay in macOS Keychain") {
                        ForEach(viewModel.model.rows.filter { $0.kind == .apiKey }) { row in
                            ProviderRow(
                                row: row,
                                onAddKey: row.id.apiKeyID.map { id in { viewModel.beginEdit(id) } },
                                onRemoveKey: row.id.apiKeyID.map { id in { viewModel.deleteKey(id) } },
                                onTest: { viewModel.testProviders() }
                            )
                        }

                        if let editingProvider = viewModel.editingProvider {
                            APIKeyInlineEditor(
                                provider: editingProvider,
                                keyInput: $viewModel.keyInput,
                                errorText: viewModel.saveErrorText,
                                onSave: { viewModel.saveKey() },
                                onCancel: {
                                    viewModel.cancelEdit()
                                }
                            )
                            .padding(.top, 8)
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}

struct AccountsToolbar: View {
    let refreshNow: () -> Void
    let onTest: () -> Void
    let isTesting: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Accounts")
                    .font(.title2.bold())
                Text("Configure local agents and API-balance providers from one place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button("↻ Test Providers", action: onTest)
                    .disabled(isTesting)
                Button("Refresh Now", action: refreshNow)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(height: 78)
    }
}

struct SummaryMetrics: View {
    let model: AccountSettingsModel

    var body: some View {
        HStack(spacing: 10) {
            MetricCard(
                label: "Local agents",
                value: localAgentsText,
                note: localAgentsNote
            )
            MetricCard(
                label: "API balance",
                value: apiBalanceText,
                note: apiBalanceNote
            )
            MetricCard(
                label: "Shared state",
                value: sharedStateText,
                note: sharedStateNote
            )
        }
    }

    private var localAgentsText: String {
        let ready = model.rows.filter { $0.kind == .localAgent && $0.configured }.count
        return "\(ready) ready"
    }

    private var localAgentsNote: String {
        let names = model.rows.filter { $0.kind == .localAgent && $0.configured }.map(\.name)
        return names.isEmpty ? "None configured" : names.joined(separator: ", ")
    }

    private var apiBalanceText: String {
        let active = model.rows.filter { $0.kind == .apiKey && $0.configured }.count
        return "\(active) active"
    }

    private var apiBalanceNote: String {
        let missing = model.rows.filter { $0.kind == .apiKey && !$0.configured }.map(\.name)
        return missing.isEmpty ? "All keys configured" : "\(missing.joined(separator: ", ")) key missing"
    }

    private var sharedStateText: String {
        model.payload != nil ? "Live" : "Unavailable"
    }

    private var sharedStateNote: String {
        model.payload != nil ? "App Group usage.json available" : "No data available"
    }
}

struct MetricCard: View {
    let label: String
    let value: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold))
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

struct ProviderSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content
            }
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

struct ProviderRow: View {
    let row: AccountRowState
    var onAddKey: (() -> Void)?
    var onRemoveKey: (() -> Void)?
    var onTest: (() -> Void)?
    var onToggleProbe: (() -> Void)?
    var onLoginHelp: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ProviderLogo(id: row.id)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 14, weight: .bold))
                    if let detailText = row.detailText {
                        Tag(text: detailText)
                    }
                }
                Text(row.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                if let balanceSummary = row.balanceSummary {
                    Text(balanceSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProviderStatus(configured: row.configured)

                rowActionButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(minHeight: 68)
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.black.opacity(0.04)),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private var rowActionButton: some View {
        switch row.id.kind {
        case .localAgent:
            if row.id == .codex {
                Button(row.configured ? "Settings" : "Enable Probe") {
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
                Button("Edit") { onAddKey?() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button("Add Key") { onAddKey?() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }
}

struct ProviderLogo: View {
    let id: AccountProviderID

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(logoColor)
            Text(logoText)
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(.white)
        }
    }

    private var logoColor: Color {
        switch id {
        case .claude: return Color(red: 0.851, green: 0.467, blue: 0.341)
        case .codex: return Color(red: 0.482, green: 0.514, blue: 0.961)
        case .kimi: return Color(red: 0.067, green: 0.067, blue: 0.067)
        case .deepseek: return Color(red: 0.310, green: 0.427, blue: 0.478)
        case .siliconflow: return Color(red: 0.961, green: 0.424, blue: 0.424)
        case .openrouter: return Color(red: 0.545, green: 0.361, blue: 0.965)
        }
    }

    private var logoText: String {
        switch id {
        case .claude: return "✳"
        case .codex: return "◆"
        case .kimi: return "K"
        case .deepseek: return "D"
        case .siliconflow: return "S"
        case .openrouter: return "O"
        }
    }
}

struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(.secondary)
            .cornerRadius(5)
    }
}

struct ProviderStatus: View {
    let configured: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(configured ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(configured ? "Active" : "Missing")
                .font(.system(size: 12, weight: .semibold))
        }
    }
}

struct APIKeyInlineEditor: View {
    let provider: APIKeyProviderID
    @Binding var keyInput: String
    let errorText: String?
    let onSave: () -> Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(provider.name) API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("API Key", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button("Cancel", action: onCancel)
            Button("Save") {
                _ = onSave()
            }
            .buttonStyle(.borderedProminent)
            .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Refresh Page

struct RefreshPage: View {
    let refreshNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Refresh")
                        .font(.title2.bold())
                    Text("Pull fresh usage data for all providers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(height: 78)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text("All display layers read from the shared usage state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Refresh Now", action: refreshNow)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(24)

            Spacer()
        }
    }
}

// MARK: - Displays Page

struct DisplayLayerActions {
    let installUbersicht: () throws -> Void
    let openUbersichtFolder: () throws -> Void
    let refreshWidgetKit: () -> Void
    let openWidgetGallery: () throws -> Void
    let installTouchBar: () throws -> Void
    let openTouchBar: () throws -> Void
}

struct DisplaysPage: View {
    let displayStore: DisplayLayerStore
    let actions: DisplayLayerActions
    @State private var resultText: String?
    @State private var busyLayer: DisplayLayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Displays")
                        .font(.title2.bold())
                    Text("Optional presentation layers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(height: 78)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        DisplayCard(
                            title: "Übersicht Widget",
                            description: "Desktop widget reads shared state first, then falls back to bundled fetcher.",
                            status: displayStore.status(for: .ubersicht),
                            actions: {
                                HStack(spacing: 8) {
                                    Button("Install / Update") { run(.ubersicht, "Übersicht updated", actions.installUbersicht) }
                                        .disabled(busyLayer != nil)
                                        .buttonStyle(.borderedProminent)
                                    Button("Open Folder") { run(.ubersicht, "Übersicht folder opened", actions.openUbersichtFolder) }
                                        .disabled(busyLayer != nil)
                                }
                            }
                        )

                        DisplayCard(
                            title: "macOS Widget",
                            description: "Bundled WidgetKit extension. Use refresh when timelines look stale.",
                            status: displayStore.status(for: .widgetKit),
                            actions: {
                                HStack(spacing: 8) {
                                    Button("Refresh Timelines") {
                                        actions.refreshWidgetKit()
                                        resultText = "Widget timelines refreshed"
                                    }
                                    .disabled(busyLayer != nil)
                                    .buttonStyle(.borderedProminent)
                                    Button("Open Widget Gallery") { run(.widgetKit, "Widget gallery opened", actions.openWidgetGallery) }
                                        .disabled(busyLayer != nil)
                                }
                            }
                        )

                        DisplayCard(
                            title: "Touch Bar / Bar",
                            description: "Small always-on display for the current provider and balance state.",
                            status: displayStore.status(for: .touchBar),
                            actions: {
                                HStack(spacing: 8) {
                                    Button("Install / Update") { run(.touchBar, "Touch Bar app updated", actions.installTouchBar) }
                                        .disabled(busyLayer != nil)
                                        .buttonStyle(.borderedProminent)
                                    Button("Open App") { run(.touchBar, "Touch Bar app opened", actions.openTouchBar) }
                                        .disabled(busyLayer != nil)
                                }
                            }
                        )
                    }

                    if let resultText {
                        Text(resultText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
        }
    }

    private func run(_ layer: DisplayLayer, _ success: String, _ action: () throws -> Void) {
        busyLayer = layer
        do {
            try action()
            resultText = success
        } catch {
            resultText = error.localizedDescription
        }
        busyLayer = nil
    }
}

struct DisplayCard<Actions: View>: View {
    let title: String
    let description: String
    let status: DisplayLayerStatus
    let actions: Actions

    init(
        title: String,
        description: String,
        status: DisplayLayerStatus,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                StatusPill(installed: status.installed)
            }

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 8) {
                actions
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(Color.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

struct StatusPill: View {
    let installed: Bool

    var body: some View {
        Text(installed ? "Installed" : "Not Installed")
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(installed ? .green : .orange)
            .cornerRadius(999)
            .overlay(
                RoundedRectangle(cornerRadius: 999)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - Diagnostics Page

struct DiagnosticsPage: View {
    let usageStore: UsageStore
    let displayStore: DisplayLayerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Diagnostics")
                        .font(.title2.bold())
                    Text("Inspect shared state and display layer health.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(height: 78)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let status = usageStore.status()

                    VStack(alignment: .leading, spacing: 0) {
                        DiagnosticRow(label: "Shared usage state", value: status.available ? "Available" : "\(status.reason)")
                        ForEach(DisplayLayer.allCases) { layer in
                            let layerStatus = displayStore.status(for: layer)
                            DiagnosticRow(label: layer.title, value: layerStatus.detail)
                        }
                    }
                    .background(Color.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )

                    Text("If the widget appears blank, verify that QuotaWidget.app is Developer ID signed and that the WidgetKit extension is registered.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
        }
    }
}

struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.black.opacity(0.04)),
            alignment: .bottom
        )
    }
}
