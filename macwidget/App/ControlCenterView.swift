import SwiftUI

struct ControlCenterView: View {
    @ObservedObject var accountViewModel: AccountSettingsViewModel
    let displayStore: DisplayLayerStore
    let usageStore: UsageStore
    let refreshNow: () -> Void
    let displayActions: DisplayLayerActions

    var body: some View {
        TabView {
            AccountSettingsView(viewModel: accountViewModel)
                .tabItem { Text("Accounts") }

            RefreshPanel(refreshNow: refreshNow)
                .tabItem { Text("Refresh") }

            DisplaysPanel(displayStore: displayStore, actions: displayActions)
                .tabItem { Text("Displays") }

            DiagnosticsPanel(usageStore: usageStore, displayStore: displayStore)
                .tabItem { Text("Diagnostics") }
        }
        .frame(minWidth: 560, minHeight: 460)
    }
}

struct DisplayLayerActions {
    let installUbersicht: () throws -> Void
    let openUbersichtFolder: () throws -> Void
    let refreshWidgetKit: () -> Void
    let openWidgetGallery: () throws -> Void
    let installTouchBar: () throws -> Void
    let openTouchBar: () throws -> Void
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
    let actions: DisplayLayerActions
    @State private var resultText: String?
    @State private var busyLayer: DisplayLayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(DisplayLayer.allCases) { layer in
                let status = displayStore.status(for: layer)
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(layer.title).font(.headline)
                        Text(status.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(status.installed ? "Installed" : "Not Installed")
                        .foregroundStyle(status.installed ? .green : .orange)
                    actionButtons(for: layer)
                }
            }
            if let resultText {
                Text(resultText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func actionButtons(for layer: DisplayLayer) -> some View {
        switch layer {
        case .ubersicht:
            Button("Install / Update") { run(layer, "Übersicht updated", actions.installUbersicht) }
                .disabled(busyLayer != nil)
            Button("Open Folder") { run(layer, "Übersicht folder opened", actions.openUbersichtFolder) }
                .disabled(busyLayer != nil)
        case .widgetKit:
            Button("Refresh Timelines") {
                actions.refreshWidgetKit()
                resultText = "Widget timelines refreshed"
            }
            .disabled(busyLayer != nil)
            Button("Open Widget Gallery") { run(layer, "Widget gallery opened", actions.openWidgetGallery) }
                .disabled(busyLayer != nil)
        case .touchBar:
            Button("Install / Update") { run(layer, "Touch Bar app updated", actions.installTouchBar) }
                .disabled(busyLayer != nil)
            Button("Open App") { run(layer, "Touch Bar app opened", actions.openTouchBar) }
                .disabled(busyLayer != nil)
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

struct DiagnosticsPanel: View {
    let usageStore: UsageStore
    let displayStore: DisplayLayerStore

    var body: some View {
        let status = usageStore.status()
        VStack(alignment: .leading, spacing: 0) {
            List {
                LabeledContent("Shared usage state", value: status.available ? "Available" : "\(status.reason)")
                ForEach(DisplayLayer.allCases) { layer in
                    let layerStatus = displayStore.status(for: layer)
                    LabeledContent(layer.title, value: layerStatus.detail)
                }
            }
            Text("If the widget appears blank, verify that QuotaWidget.app is Developer ID signed and that the WidgetKit extension is registered.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}
