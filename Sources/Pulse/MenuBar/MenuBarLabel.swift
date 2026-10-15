import SwiftUI
import PulseCore

struct MenuBarLabelView: View {
    let store: AppStore

    var body: some View {
        let sys = store.snapshot.system
        let isStrained = sys.pressure == .critical || sys.cpuTotal >= 0.9

        HStack(spacing: 4) {
            Image(systemName: isStrained ? "exclamationmark.triangle.fill" : "waveform.path.ecg")
                .foregroundStyle(isStrained ? Theme.red : .primary)

            switch store.settings.menuBarMode {
            case .iconOnly:
                EmptyView()
            case .sparkline:
                HStack(spacing: 4) {
                    MiniSpark(values: Array(store.cpuHistory.recentValues.suffix(10)))
                        .frame(width: 22, height: 12)
                    Text(Format.percent(sys.cpuTotal))
                        .monospacedDigit()
                }
            case .cpuOnly:
                Text(Format.percent(sys.cpuTotal))
                    .monospacedDigit()
            case .memOnly:
                Text(Format.percent(sys.memoryFraction))
                    .monospacedDigit()
            case .cpuAndMem:
                Text("C: \(Format.percent(sys.cpuTotal))  M: \(Format.percent(sys.memoryFraction))")
                    .monospacedDigit()
            case .cpuMemNet:
                Text("C: \(Format.percent(sys.cpuTotal))  M: \(Format.percent(sys.memoryFraction))  ↓ \(Format.rate(sys.netIn))")
                    .monospacedDigit()
            case .network:
                Text("↓ \(Format.rate(sys.netIn))")
                    .monospacedDigit()
            }
        }
        .font(.system(size: 12, weight: .medium))
    }
}

struct MiniSpark: View {
    let values: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let maxVal = max(0.01, values.max() ?? 1.0)
            let step = size.width / CGFloat(values.count - 1)
            var p = Path()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height - (CGFloat(v / maxVal) * size.height)
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(p, with: .color(.primary), lineWidth: 1.2)
        }
    }
}
