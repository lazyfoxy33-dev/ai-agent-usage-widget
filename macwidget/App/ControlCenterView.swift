import SwiftUI

struct ControlCenterView: View {
    @ObservedObject var accountViewModel: AccountSettingsViewModel
    let displayStore: DisplayLayerStore
    let usageStore: UsageStore
    let refreshNow: () -> Void

    var body: some View {
        TabView {
            AccountSettingsView(viewModel: accountViewModel)
                .tabItem { Text("Accounts") }

            RefreshPanel(refreshNow: refreshNow)
                .tabItem { Text("Refresh") }

            DisplaysPanel(displayStore: displayStore)
                .tabItem { Text("Displays") }

            DiagnosticsPanel(usageStore: usageStore, displayStore: displayStore)
                .tabItem { Text("Diagnostics") }
        }
        .frame(minWidth: 560, minHeight: 460)
    }
}

struct RefreshPanel: View {
    let refreshNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Refresh")
                .font(.title2)
            Text("QuotaWidget refreshes usage data for every display layer.")
                .foregroundStyle(.secondary)
            Button("Refresh Now", action: refreshNow)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct DisplaysPanel: View {
    let displayStore: DisplayLayerStore

    var body: some View {
        List(DisplayLayer.allCases) { layer in
            let status = displayStore.status(for: layer)
            HStack {
                VStack(alignment: .leading) {
                    Text(layer.title).font(.headline)
                    Text(status.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(status.installed ? "Installed" : "Not Installed")
                    .foregroundStyle(status.installed ? .green : .orange)
            }
        }
    }
}

struct DiagnosticsPanel: View {
    let usageStore: UsageStore
    let displayStore: DisplayLayerStore

    var body: some View {
        let status = usageStore.status()
        List {
            LabeledContent("Shared usage state", value: status.available ? "Available" : "\(status.reason)")
            ForEach(DisplayLayer.allCases) { layer in
                let layerStatus = displayStore.status(for: layer)
                LabeledContent(layer.title, value: layerStatus.detail)
            }
        }
    }
}
