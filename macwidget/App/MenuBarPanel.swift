import AppKit
import SwiftUI

/// Wires the panel to the model: reloads on open and supplies the actions.
struct MenuBarPanelHost: View {
    @ObservedObject var model: QuotaWidgetModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        MenuBarPanel(
            rows: model.menuRows,
            status: model.status,
            connected: model.menuConnected,
            onRefresh: { model.refreshAllProviders() },
            onSettings: { SettingsPresenter.app(openSettings: { openSettings() }).present() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        .onAppear { model.reloadMenuRows() }
    }
}

/// The status-bar dropdown: a compact panel rather than a plain menu.
///
/// Rows follow the 菜单显示 order, each with its brand icon, its figures and a
/// status dot; the header carries the connection count and the footer the actions.
/// Data is passed in, so the panel can be rendered and inspected on its own.
struct MenuBarPanel: View {
    let rows: [MenuProviderRow]
    let status: String
    let connected: Int
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    private var total: Int { AccountProviderID.allCases.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if rows.isEmpty {
                Text("暂无数据")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 1) {
                    ForEach(rows) { row in
                        ProviderRowView(row: row)
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            footer
        }
        .frame(width: 336)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("AI 用量组件")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                connectionPill
            }
            Text(status)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var connectionPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(connected > 0 ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text("已连接 \(connected)/\(total)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("立即刷新", action: onRefresh)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("设置…", action: onSettings)
                .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer()
            Button("退出", action: onQuit)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// One provider: icon, name, figures and a status dot.
struct ProviderRowView: View {
    let row: MenuProviderRow
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProviderLogo(id: row.id)
                .frame(width: 24, height: 24)
                .opacity(row.isAvailable ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(row.isAvailable ? .primary : .secondary)
                    if row.isCached {
                        Text("缓存")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                    Spacer(minLength: 6)
                    trailingValue
                    statusDot
                }
                detail
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(hovering ? Color.primary.opacity(0.06) : Color.clear)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var trailingValue: some View {
        switch row.metric {
        case .balance(let amount, _, _, _):
            Text(amount)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
        case .quota(let fiveH, let weekly, _):
            if let tightest = [fiveH, weekly].compactMap({ $0 }).min() {
                Text("\(tightest)%")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tightest <= 20 ? Color.orange : Color.primary)
            }
        case .unavailable:
            EmptyView()
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 6, height: 6)
            .padding(.top, 5)
    }

    private var dotColor: Color {
        if !row.isAvailable { return Color.secondary.opacity(0.5) }
        return row.isCached ? Color.orange : Color.green
    }

    @ViewBuilder
    private var detail: some View {
        switch row.metric {
        case .quota(let fiveH, let weekly, _):
            HStack(spacing: 10) {
                if let fiveH {
                    WindowBar(label: "5H", remaining: fiveH, tint: BrandPalette.accent(for: row.id))
                }
                if let weekly {
                    WindowBar(label: "周", remaining: weekly, tint: BrandPalette.accent(for: row.id).opacity(0.55))
                }
            }
        case .balance(_, let trend, let daysLeft, let cached):
            VStack(alignment: .leading, spacing: 3) {
                if let daysLeft, daysLeft > 0 {
                    MiniBar(
                        fraction: min(1, Double(daysLeft) / 30),
                        tint: cached ? Color.secondary : BrandPalette.accent(for: row.id)
                    )
                    .frame(width: 120)
                }
                if let trend {
                    Text(trend)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        case .unavailable(let reason):
            Text(reason)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }
}

/// Label + bar + percentage for one quota window.
struct WindowBar: View {
    let label: String
    let remaining: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
            MiniBar(fraction: Double(remaining) / 100, tint: tint)
                .frame(width: 68)
            Text("\(remaining)%")
                .font(.system(size: 9.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

/// A slim capsule progress bar.
struct MiniBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: max(2, geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 5)
    }
}

/// The brand colours the quota bars and the app share.
enum BrandPalette {
    static func accent(for id: AccountProviderID) -> Color {
        switch id {
        case .claude:
            return Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
        case .codex:
            return Color(red: 0x7B / 255, green: 0x83 / 255, blue: 0xF5 / 255)
        case .kimi:
            return Color(red: 0x2E / 255, green: 0x8B / 255, blue: 0xFF / 255)
        case .deepseek:
            return Color(red: 0x55 / 255, green: 0x8B / 255, blue: 0xFF / 255)
        case .siliconflow:
            return Color(red: 0xF2 / 255, green: 0x72 / 255, blue: 0x72 / 255)
        case .openrouter:
            return Color(red: 0xA0 / 255, green: 0x7B / 255, blue: 0xFF / 255)
        }
    }
}
