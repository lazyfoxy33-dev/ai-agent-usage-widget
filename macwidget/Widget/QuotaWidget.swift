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
    let ink: Color
    let sub: Color
    let background: Color
}

private extension ProviderKind {
    var accentColor: Color {
        switch self {
        case .claude:
            return Color(red: 0.85098, green: 0.46667, blue: 0.34118)   // #D97757
        case .codex:
            return Color(red: 0.48235, green: 0.51373, blue: 0.96078)   // #7B83F5
        case .kimi:
            return Color(red: 0.07843, green: 0.47059, blue: 1.0)       // #1478FF
        }
    }

    private var tintLight: Color {
        switch self {
        case .claude: return Color(red: 0.98039, green: 0.96863, blue: 0.95294) // #FAF7F3
        case .codex:  return Color(red: 0.96471, green: 0.96471, blue: 0.98431) // #F6F6FB
        case .kimi:   return Color(red: 0.95686, green: 0.96863, blue: 0.98824) // #F4F7FC
        }
    }

    private var tintDark: Color {
        switch self {
        case .claude: return Color(red: 0.12941, green: 0.12157, blue: 0.10980) // #211F1C
        case .codex:  return Color(red: 0.10588, green: 0.10588, blue: 0.13725) // #1B1B23
        case .kimi:   return Color(red: 0.09412, green: 0.10980, blue: 0.14118) // #181C24
        }
    }

    func palette(isDark: Bool) -> Palette {
        let ink = isDark
            ? Color(red: 0.92549, green: 0.91765, blue: 0.90196) // #ECEAE6
            : Color(red: 0.14902, green: 0.13725, blue: 0.12157) // #26231F
        let sub = isDark
            ? Color(red: 0.54902, green: 0.53333, blue: 0.49804) // #8c887f
            : Color(red: 0.60392, green: 0.57255, blue: 0.52549) // #9a9286
        return Palette(
            accent: accentColor,
            ink: ink,
            sub: sub,
            background: isDark ? tintDark : tintLight
        )
    }
}

/// In-hue emphasis: darken in light mode, brighten in dark mode.
private func emphasis(_ accent: Color, used: Double, isDark: Bool) -> Color {
    let level = used >= 90 ? 2 : used >= 70 ? 1 : 0
    guard level > 0 else { return accent }

    let base = NSColor(accent).usingColorSpace(.sRGB) ?? NSColor(accent)
    let r = base.redComponent
    let g = base.greenComponent
    let b = base.blueComponent

    if isDark {
        let t = [0.0, 0.20, 0.38][level]
        return Color(NSColor(
            red: r + (1.0 - r) * t,
            green: g + (1.0 - g) * t,
            blue: b + (1.0 - b) * t,
            alpha: 1.0
        ))
    } else {
        let f = [1.0, 0.84, 0.70][level]
        return Color(NSColor(
            red: r * f,
            green: g * f,
            blue: b * f,
            alpha: 1.0
        ))
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
    let isDark: Bool
    var diameter: CGFloat = 56

    var body: some View {
        let five = provider.fiveH?.percentage ?? 0
        let week = provider.weekly?.percentage ?? 0
        let weekColor = emphasis(palette.accent, used: week, isDark: isDark)
        let fiveColor = emphasis(palette.accent, used: five, isDark: isDark)
        let urgent: (pct: Double, label: String) = five >= week
            ? (five, "5H")
            : (week, "Weekly")
        let urgentColor = emphasis(palette.accent, used: urgent.pct, isDark: isDark)

        let lw = diameter * 0.12
        let inset = lw + 3
        let trackColor = isDark
            ? Color.white.opacity(0.13)
            : Color.black.opacity(0.09)

        ZStack {
            Circle().stroke(trackColor, lineWidth: lw)
            Circle().trim(from: 0, to: min(1, max(0, week / 100)))
                .stroke(weekColor, style: .init(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle().inset(by: inset).stroke(trackColor, lineWidth: lw)
            Circle().inset(by: inset).trim(from: 0, to: min(1, max(0, five / 100)))
                .stroke(fiveColor, style: .init(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text("\(Int(urgent.pct))%")
                    .font(.system(
                        size: urgent.pct >= 100 ? diameter * 0.22 : diameter * 0.26,
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundStyle(urgentColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text(ProviderPresentation.code(for: urgent.label).uppercased())
                    .font(.system(size: diameter * 0.11, weight: .semibold))
                    .foregroundStyle(palette.sub)
                    .lineLimit(1)
            }
            .frame(width: diameter - 2 * (inset + lw) - 2)
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct MetricRow: View {
    let code: String
    let pct: Double
    let reset: String
    let accent: Color
    let ink: Color
    let sub: Color
    let isDark: Bool
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 2 : 4) {
            Circle()
                .fill(emphasis(accent, used: pct, isDark: isDark))
                .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
            Text(code)
                .font(.system(size: compact ? 9.5 : 12, weight: .medium))
                .foregroundStyle(ink)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 2)
            Text("↻ \(reset)")
                .font(.system(size: compact ? 8 : 9.5))
                .foregroundStyle(sub)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(Int(pct))%")
                .font(.system(size: compact ? 9.5 : 12, weight: .semibold))
                .foregroundStyle(emphasis(accent, used: pct, isDark: isDark))
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: compact ? 24 : 34, alignment: .trailing)
        }
    }
}

private struct SmallCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let kind: ProviderKind
    let provider: UsageProvider

    private var isDark: Bool { colorScheme == .dark }
    private var p: Palette { kind.palette(isDark: isDark) }

    var body: some View {
        VStack(spacing: 8) {
            header

            if provider.ok, let five = provider.fiveH, let week = provider.weekly {
                let stale = provider.isStale
                if stale {
                    Text(ProviderPresentation.cachedMessage())
                        .font(.system(size: 10))
                        .foregroundStyle(p.sub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                DualRing(provider: provider, palette: p, isDark: isDark, diameter: 54)
                    .opacity(stale ? 0.55 : 1)

                VStack(spacing: 6) {
                    MetricRow(
                        code: "5H",
                        pct: five.percentage,
                        reset: ProviderPresentation.countdown(until: five.resetsAt),
                        accent: p.accent,
                        ink: p.ink,
                        sub: p.sub,
                        isDark: isDark
                    )
                    MetricRow(
                        code: "Wk",
                        pct: week.percentage,
                        reset: ProviderPresentation.countdown(until: week.resetsAt),
                        accent: p.accent,
                        ink: p.ink,
                        sub: p.sub,
                        isDark: isDark
                    )
                }
                .opacity(stale ? 0.55 : 1)
            } else {
                Spacer(minLength: 0)
                Text(ProviderPresentation.message(for: kind, provider: provider))
                    .font(.system(size: 11))
                    .foregroundStyle(p.sub)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.background)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            ProviderMark(kind: kind).frame(width: 18, height: 18)
            Text(kind.rawValue)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(p.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
    }
}

private struct MediumColumn: View {
    @Environment(\.colorScheme) private var colorScheme
    let kind: ProviderKind
    let provider: UsageProvider

    private var isDark: Bool { colorScheme == .dark }
    private var p: Palette { kind.palette(isDark: isDark) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 0)

            if provider.ok, let five = provider.fiveH, let week = provider.weekly {
                let stale = provider.isStale
                if stale {
                    Text(ProviderPresentation.cachedMessage())
                        .font(.system(size: 9.5))
                        .foregroundStyle(p.sub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                DualRing(
                    provider: provider,
                    palette: p,
                    isDark: isDark,
                    diameter: WidgetLayout.mediumRingSize
                )
                .opacity(stale ? 0.55 : 1)

                Spacer(minLength: 0)
                VStack(spacing: 5) {
                    MetricRow(
                        code: "5H",
                        pct: five.percentage,
                        reset: ProviderPresentation.countdown(until: five.resetsAt),
                        accent: p.accent,
                        ink: p.ink,
                        sub: p.sub,
                        isDark: isDark,
                        compact: true
                    )
                    MetricRow(
                        code: "Wk",
                        pct: week.percentage,
                        reset: ProviderPresentation.countdown(until: week.resetsAt),
                        accent: p.accent,
                        ink: p.ink,
                        sub: p.sub,
                        isDark: isDark,
                        compact: true
                    )
                }
                .opacity(stale ? 0.55 : 1)
            } else {
                Spacer(minLength: 0)
                Text(ProviderPresentation.message(for: kind, provider: provider))
                    .font(.system(size: 9.5))
                    .foregroundStyle(p.sub)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 11).padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 4) {
            ProviderMark(kind: kind).frame(width: 14, height: 14)
            Text(kind.rawValue)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(p.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
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
