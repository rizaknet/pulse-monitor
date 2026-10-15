import SwiftUI
import Charts
import PulseCore

public struct MetricHeroChart: View {
    let points: [TimedValue]
    let color: Color
    var maxValue: Double? = nil
    var formatLabel: (Double) -> String = { Format.percent($0) }

    public init(points: [TimedValue], color: Color, maxValue: Double? = nil, formatLabel: @escaping (Double) -> String = { Format.percent($0) }) {
        self.points = points
        self.color = color
        self.maxValue = maxValue
        self.formatLabel = formatLabel
    }

    public var body: some View {
        let maxV = maxValue ?? max(points.map(\.value).max() ?? 1.0, 1e-6) * 1.15

        Chart(points, id: \.date) { pt in
            AreaMark(x: .value("Time", pt.date), y: .value("Value", min(pt.value, maxV)))
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.24), color.opacity(0)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Time", pt.date), y: .value("Value", min(pt.value, maxV)))
                .interpolationMethod(.monotone)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
        .chartYScale(domain: 0...maxV)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, maxV / 2, maxV]) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Theme.inkTertiary.opacity(0.4))
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text(formatLabel(d))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}
