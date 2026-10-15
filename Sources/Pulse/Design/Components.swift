import SwiftUI
import Charts
import PulseCore

// MARK: Containers

struct PulseCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

/// Tinted icon + title + optional trailing chevron, the header used by every card.
struct CardHeader: View {
    let title: String
    let icon: String
    let color: Color
    var chevron = true

    var body: some View {
        HStack(spacing: 8) {
            IconTile(symbol: icon, color: color, size: 22)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
            Spacer(minLength: 4)
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.inkTertiary)
            }
        }
    }
}

struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct SectionTitle: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
            Spacer()
            if let trailing {
                Button(trailing) { action?() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

// MARK: Numbers

/// Large figure with a smaller unit beside it: "52.02 GB".
struct BigNumber: View {
    let value: String
    let unit: String
    var size: CGFloat = 32

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: size, weight: .bold))
                .tracking(-0.6)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            if !unit.isEmpty {
                Text(unit).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Small label over a value, optionally with a coloured dot (legend style).
struct StatColumn: View {
    let label: String
    let value: String
    var dot: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
            }
            Text(value).font(.system(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.ink).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var symbol: String? = nil

    init(_ text: String, color: Color, symbol: String? = nil) {
        self.text = text; self.color = color; self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.13), in: Capsule())
    }
}

// MARK: Graphics (Canvas-based: far cheaper than Charts for small live graphs)

/// Capsule bars on a faint tinted track, newest on the right. Quiet values render as short stubs.
struct BarSpark: View {
    let values: [Double]
    let color: Color
    var maxValue: Double? = nil
    var count = 44

    var body: some View {
        Canvas { ctx, size in
            let bg = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 7, style: .continuous)
            ctx.fill(bg, with: .color(color.opacity(0.10)))

            let vals = Array(values.suffix(count))
            let m = max(maxValue ?? (vals.max() ?? 1), 1e-9)
            let inset: CGFloat = 5
            let w = size.width - inset * 2, h = size.height - inset * 2
            let slot = w / CGFloat(count)
            let barW = max(2, slot * 0.6)
            let offset = count - vals.count
            for (i, v) in vals.enumerated() {
                let frac = CGFloat(min(max(v / m, 0), 1))
                let bh = max(3, h * frac)
                let x = inset + CGFloat(i + offset) * slot + (slot - barW) / 2
                let r = CGRect(x: x, y: inset + h - bh, width: barW, height: bh)
                ctx.fill(Path(roundedRect: r, cornerRadius: barW / 2), with: .color(color))
            }
        }
    }
}

/// Smooth line with a soft gradient fill.
struct LineSpark: View {
    let values: [Double]
    let color: Color
    var maxValue: Double? = nil

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else {
                var p = Path(); p.move(to: CGPoint(x: 0, y: size.height - 1)); p.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                ctx.stroke(p, with: .color(color.opacity(0.5)), lineWidth: 1.5)
                return
            }
            let m = max(maxValue ?? (values.max() ?? 1), 1e-9)
            let step = size.width / CGFloat(values.count - 1)
            let pts = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * step, y: size.height - 1.5 - (size.height - 3) * CGFloat(min(max(v / m, 0), 1)))
            }
            var line = Path()
            line.move(to: pts[0])
            for i in 1..<pts.count {
                let a = pts[i - 1], b = pts[i]
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                line.addQuadCurve(to: mid, control: a)
                if i == pts.count - 1 { line.addQuadCurve(to: b, control: b) }
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.28), color.opacity(0.02)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}

struct InlineBar: View {
    let value: Double // 0…1
    let color: Color
    var width: CGFloat = 44
    var height: CGFloat = 5

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(color.opacity(0.14))
            Capsule().fill(color).frame(width: max(value > 0.002 ? height : 0, width * CGFloat(min(max(value, 0), 1))))
        }
        .frame(width: width, height: height)
    }
}

/// Fill-width progress bar (disk usage, battery level).
struct ProgressTrack: View {
    let value: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule().fill(color).frame(width: max(height, g.size.width * CGFloat(min(max(value, 0), 1))))
            }
        }
        .frame(height: height)
    }
}

struct DonutSegment: Identifiable {
    let id: String
    let label: String
    let value: Double
    let color: Color
    var detail: String
}

/// Ring chart with a centre caption and a legend to its right.
struct DonutCard: View {
    let title: String
    let icon: String
    let color: Color
    let segments: [DonutSegment]
    let centerValue: String
    let centerCaption: String
    var appIcons: [String: AppUsage] = [:]

    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: title, icon: icon, color: color, chevron: false)
                HStack(spacing: 18) {
                    ZStack {
                        Chart(segments) { s in
                            SectorMark(angle: .value("v", max(s.value, 0.0001)), innerRadius: .ratio(0.68), angularInset: 1.2)
                                .foregroundStyle(s.color)
                                .cornerRadius(2)
                        }
                        .chartLegend(.hidden)
                        VStack(spacing: 0) {
                            Text(centerValue).font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(Theme.ink)
                            Text(centerCaption).font(.system(size: 10)).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .frame(width: 112, height: 112)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(segments) { s in
                            HStack(spacing: 6) {
                                Circle().fill(s.color).frame(width: 7, height: 7)
                                if let app = appIcons[s.id] { AppIconView(app: app, size: 14) }
                                Text(s.label).font(.system(size: 12)).foregroundStyle(Theme.ink).lineLimit(1)
                                Spacer(minLength: 6)
                                Text(s.detail).font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.inkSecondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: App identity

struct AppIconView: View {
    let app: AppUsage
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let bundle = app.bundlePath {
                Image(nsImage: IconCache.icon(forPath: bundle)).resizable().interpolation(.high)
            } else if app.kind == .system {
                Image(systemName: "apple.logo").resizable().scaledToFit().padding(size * 0.12).foregroundStyle(Theme.inkSecondary)
            } else {
                Image(systemName: "terminal.fill").resizable().scaledToFit().padding(size * 0.14).foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Hover highlight helper.
struct Hoverable: ViewModifier {
    @State private var hover = false
    var radius: CGFloat = 10
    func body(content: Content) -> some View {
        content
            .background(hover ? Theme.cardHover : .clear, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hover = $0 }
    }
}

extension View {
    func hoverHighlight(radius: CGFloat = 10) -> some View { modifier(Hoverable(radius: radius)) }
}
