import SwiftUI
import WidgetKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let payload: UsagePayload?
}

struct QuotaTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: Date(), payload: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(QuotaEntry(date: Date(), payload: .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let json = try? UsageStore().read()
        let payload = json.flatMap { try? UsagePayload.decode(Data($0.utf8)) }
        completion(Timeline(
            entries: [QuotaEntry(date: Date(), payload: payload)],
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

private struct UsageRing: View {
    let provider: UsageProvider
    let palette: Palette

    var body: some View {
        ZStack {
            ring(provider.weekly?.percentage ?? 0, color: palette.soft, size: 72)
            ring(provider.fiveH?.percentage ?? 0, color: palette.accent, size: 52)
            VStack(spacing: 1) {
                let percentage = Int(provider.fiveH?.percentage ?? 0)
                Text("\(percentage)%")
                    .font(.system(
                        size: percentage >= 100 ? 14 : 19,
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundStyle(palette.accent)
                Text("5H")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(palette.sub)
            }
        }
        .frame(width: 80, height: 80)
        .opacity(provider.isStale ? 0.55 : 1)
    }

    private func ring(_ value: Double, color: Color, size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.13), lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(1, max(0, value / 100)))
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

private struct CompactUsageRing: View {
    let provider: UsageProvider
    let palette: Palette

    var body: some View {
        ZStack {
            ring(
                provider.weekly?.percentage ?? 0,
                color: palette.soft,
                size: WidgetLayout.mediumRingSize
            )
            ring(
                provider.fiveH?.percentage ?? 0,
                color: palette.accent,
                size: WidgetLayout.mediumRingSize - 14
            )
            Text("\(Int(provider.fiveH?.percentage ?? 0))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(palette.accent)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(width: WidgetLayout.mediumRingSize + 4, height: WidgetLayout.mediumRingSize + 4)
        .opacity(provider.isStale ? 0.55 : 1)
    }

    private func ring(_ value: Double, color: Color, size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.13), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(1, max(0, value / 100)))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

private struct ProviderCard: View {
    let kind: ProviderKind
    let provider: UsageProvider
    let compact: Bool

    private var palette: Palette { kind.palette }

    var body: some View {
        HStack(spacing: compact ? 6 : 12) {
            UsageRing(provider: provider, palette: palette)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    ProviderMark(kind: kind)
                    Text(kind.rawValue)
                        .font(.system(size: compact ? 11 : 14, weight: .bold))
                }
                .foregroundStyle(palette.ink)
                if provider.ok, let five = provider.fiveH, let week = provider.weekly {
                    metric("5 小时", window: five, color: palette.accent)
                    metric("本周", window: week, color: palette.soft)
                    if provider.isStale {
                        Text("缓存数据 · 等待刷新")
                            .font(.system(size: 8))
                            .foregroundStyle(palette.sub)
                    }
                } else {
                    Text(ProviderPresentation.message(for: kind, provider: provider))
                        .font(.system(size: 8.5))
                        .foregroundStyle(palette.sub)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 7 : 12)
        .background(palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metric(_ label: String, window: UsageWindow, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label).font(.system(size: 8.5, weight: .semibold))
                Spacer(minLength: 2)
                Text("\(Int(window.percentage))%")
                    .font(.system(size: 9.5, weight: .bold))
            }
            Text(ProviderPresentation.countdown(until: window.resetsAt))
                .font(.system(size: 7))
                .foregroundStyle(palette.sub)
                .padding(.leading, 10)
        }
        .foregroundStyle(palette.ink)
    }
}

private struct MediumProviderColumn: View {
    let kind: ProviderKind
    let provider: UsageProvider

    private var palette: Palette { kind.palette }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ProviderMark(kind: kind)
                    .frame(width: 16, height: 16)
                Text(kind.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            CompactUsageRing(provider: provider, palette: palette)

            if provider.ok, let five = provider.fiveH, let week = provider.weekly {
                compactMetric("5H", percentage: five.percentage, color: palette.accent)
                compactMetric("周", percentage: week.percentage, color: palette.soft)
            } else {
                Text(ProviderPresentation.message(for: kind, provider: provider))
                    .font(.system(size: 7.5))
                    .foregroundStyle(palette.sub)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 5)
        .background(palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func compactMetric(_ label: String, percentage: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
            Spacer(minLength: 1)
            Text("\(Int(percentage))%").fontWeight(.bold)
        }
        .font(.system(size: 8))
        .foregroundStyle(palette.ink)
    }
}

private struct ProviderMark: View {
    let kind: ProviderKind

    var body: some View {
        Group {
            switch kind {
            case .claude:
                Text("✳")
                    .font(.system(size: 18))
                    .foregroundStyle(kind.palette.accent)
            case .codex:
                Image("codex-app").resizable().scaledToFit()
            case .kimi:
                Image("kimi-code").resizable().scaledToFit()
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct QuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuotaEntry

    var body: some View {
        if let payload = entry.payload {
            if family == .systemSmall {
                ProviderCard(kind: .claude, provider: payload.claude, compact: true)
                    .containerBackground(.clear, for: .widget)
            } else {
                HStack(spacing: 5) {
                    MediumProviderColumn(kind: .claude, provider: payload.claude)
                    MediumProviderColumn(kind: .codex, provider: payload.codex)
                    MediumProviderColumn(kind: .kimi, provider: payload.kimi)
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
