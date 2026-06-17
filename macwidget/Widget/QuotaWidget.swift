import AppKit
import SwiftUI
import WidgetKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let payload: UsagePayload?
    var active: String? = nil
}

struct QuotaTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: Date(), payload: .preview, active: "claude")
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(QuotaEntry(date: Date(), payload: .preview, active: "claude"))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let json = try? UsageStore().read()
        let payload = json.flatMap { try? UsagePayload.decode(Data($0.utf8)) }
        let active = UsageStore().readActive() ?? "claude"
        completion(Timeline(
            entries: [QuotaEntry(date: Date(), payload: payload, active: active)],
            policy: .after(Date().addingTimeInterval(25 * 60))
        ))
    }
}

private struct Palette {
    let accent: Color
    let soft: Color
    let ink: Color
    let sub: Color
    let background: LinearGradient
}

private extension ProviderKind {
    var palette: Palette {
        switch self {
        case .claude:
            Palette(
                accent: Color(red: 0.85, green: 0.47, blue: 0.34),
                soft: Color(red: 0.89, green: 0.65, blue: 0.50),
                ink: Color(red: 0.15, green: 0.14, blue: 0.12),
                sub: Color(red: 0.60, green: 0.57, blue: 0.53),
                background: LinearGradient(
                    colors: [.init(red: 0.98, green: 0.98, blue: 0.96),
                             .init(red: 0.94, green: 0.93, blue: 0.90)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        case .codex:
            Palette(
                accent: Color(red: 0.40, green: 0.46, blue: 1.0),
                soft: Color(red: 0.65, green: 0.55, blue: 0.98),
                ink: Color(red: 0.93, green: 0.93, blue: 0.93),
                sub: Color(red: 0.53, green: 0.53, blue: 0.58),
                background: LinearGradient(
                    colors: [.init(red: 0.09, green: 0.09, blue: 0.10),
                             .init(red: 0.05, green: 0.05, blue: 0.06)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        case .kimi:
            Palette(
                accent: Color(red: 0.08, green: 0.47, blue: 1.0),
                soft: Color(red: 0.15, green: 0.17, blue: 0.20),
                ink: Color(red: 0.09, green: 0.09, blue: 0.11),
                sub: Color(red: 0.45, green: 0.47, blue: 0.52),
                background: LinearGradient(
                    colors: [.init(red: 0.98, green: 0.98, blue: 0.99),
                             .init(red: 0.94, green: 0.95, blue: 0.97)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }
}

private struct ProviderMark: View {
    let kind: ProviderKind

    private var assetName: String {
        switch kind {
        case .claude: return "claude-app"
        case .codex: return "codex-app"
        case .kimi: return "kimi-code"
        }
    }

    // SwiftUI 的 Image("name") 在 macOS 上只认资源目录，散放的 PNG 需从 bundle 直接加载
    private var icon: Image {
        if let url = Bundle.main.url(forResource: assetName, withExtension: "png"),
           let ns = NSImage(contentsOf: url) {
            return Image(nsImage: ns)
        }
        return Image(systemName: "app.dashed")
    }

    var body: some View {
        icon
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct DualRing: View {
    let provider: UsageProvider
    let palette: Palette
    var diameter: CGFloat = 56

    var body: some View {
        let five = provider.fiveH?.percentage ?? 0
        let week = provider.weekly?.percentage ?? 0
        let lw = diameter * 0.12
        let inset = lw + 3
        ZStack {
            Circle().stroke(palette.soft.opacity(0.22), lineWidth: lw)
            Circle().trim(from: 0, to: min(1, max(0, week/100)))
                .stroke(palette.soft, style: .init(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle().inset(by: inset).stroke(palette.accent.opacity(0.15), lineWidth: lw)
            Circle().inset(by: inset).trim(from: 0, to: min(1, max(0, five/100)))
                .stroke(palette.accent, style: .init(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(five))%")
                .font(.system(size: diameter * 0.24, weight: .bold, design: .rounded))
                .foregroundStyle(palette.accent)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(width: diameter - 2 * (inset + lw) - 2)
        }
        .frame(width: diameter, height: diameter)
        .opacity(provider.isStale ? 0.6 : 1)
    }
}

private struct MetricRow: View {
    let label: String
    let pct: Double
    let resetsAt: TimeInterval?
    let dot: Color
    let palette: Palette
    var valueColor: Color
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle().fill(dot).frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
                Text(label).font(.system(size: compact ? 11 : 12))
                Spacer(minLength: 2)
                Text("\(Int(pct))%").font(.system(size: compact ? 11 : 12, weight: .semibold)).foregroundStyle(valueColor)
            }
            .foregroundStyle(palette.ink)
            Text(ProviderPresentation.countdown(until: resetsAt))
                .font(.system(size: compact ? 8.5 : 9.5))
                .foregroundStyle(palette.sub)
                .padding(.leading, compact ? 9 : 10)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SmallCard: View {
    let kind: ProviderKind
    let provider: UsageProvider
    private var p: Palette { kind.palette }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ProviderMark(kind: kind).frame(width: 18, height: 18)
                Text(kind.rawValue).font(.system(size: 14, weight: .medium)).foregroundStyle(p.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            if provider.ok, let five = provider.fiveH, let week = provider.weekly {
                DualRing(provider: provider, palette: p, diameter: 54)
                VStack(spacing: 6) {
                    MetricRow(label: "5 小时", pct: five.percentage, resetsAt: five.resetsAt, dot: p.accent, palette: p, valueColor: p.accent)
                    MetricRow(label: "Weekly", pct: week.percentage, resetsAt: week.resetsAt, dot: p.soft, palette: p, valueColor: p.ink)
                }
            } else {
                Spacer(minLength: 0)
                Text(ProviderPresentation.message(for: kind, provider: provider)).font(.system(size: 11)).foregroundStyle(p.sub).multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.background)
    }
}

private struct MediumColumn: View {
    let kind: ProviderKind
    let provider: UsageProvider
    private var p: Palette { kind.palette }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ProviderMark(kind: kind).frame(width: 14, height: 14)
                Text(kind.rawValue).font(.system(size: 12, weight: .medium)).foregroundStyle(p.ink).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            if provider.ok, let five = provider.fiveH, let week = provider.weekly {
                DualRing(provider: provider, palette: p, diameter: 50)
                Spacer(minLength: 0)
                VStack(spacing: 5) {
                    MetricRow(label: "5H", pct: five.percentage, resetsAt: five.resetsAt, dot: p.accent, palette: p, valueColor: p.accent, compact: true)
                    MetricRow(label: "Weekly", pct: week.percentage, resetsAt: week.resetsAt, dot: p.soft, palette: p, valueColor: p.ink, compact: true)
                }
            } else {
                Spacer(minLength: 0)
                Text(ProviderPresentation.message(for: kind, provider: provider)).font(.system(size: 9.5)).foregroundStyle(p.sub).lineLimit(3).multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 11).padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct QuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuotaEntry

    var body: some View {
        if let payload = entry.payload {
            if family == .systemSmall {
                let kind = kindFor(entry.active)
                SmallCard(kind: kind, provider: provider(payload, kind))
                    .containerBackground(.clear, for: .widget)
            } else {
                HStack(spacing: 8) {
                    MediumColumn(kind: .claude, provider: payload.claude)
                    MediumColumn(kind: .codex, provider: payload.codex)
                    MediumColumn(kind: .kimi, provider: payload.kimi)
                }
                .containerBackground(.clear, for: .widget)
            }
        } else {
            ContentUnavailableView(
                "打开 QuotaWidget",
                systemImage: "arrow.clockwise.circle",
                description: Text("伴侣 app 会刷新用量数据")
            )
            .containerBackground(.background, for: .widget)
        }
    }

    private func kindFor(_ active: String?) -> ProviderKind {
        switch active {
        case "codex": return .codex
        case "kimi": return .kimi
        default: return .claude
        }
    }

    private func provider(_ p: UsagePayload, _ kind: ProviderKind) -> UsageProvider {
        switch kind {
        case .claude: return p.claude
        case .codex: return p.codex
        case .kimi: return p.kimi
        }
    }
}

@main
struct QuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuotaWidget", provider: QuotaTimelineProvider()) {
            QuotaWidgetView(entry: $0)
        }
        .configurationDisplayName("AI Agent Usage")
        .description("Claude、Codex 与 Kimi Code 用量")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
