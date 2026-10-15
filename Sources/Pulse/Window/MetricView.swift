import SwiftUI
import PulseCore

struct MetricView: View {
    let tab: PulseTab
    @Bindable var store: AppStore
    @State private var filter: String = ""
    @State private var useHourWindow = false

    var body: some View {
        let sys = store.snapshot.system
        let windowSecs: TimeInterval = useHourWindow ? 3600 : 300
        let (history, color, format) = metricProps(sys)
        let primaryMetric = AppMetric(tab: tab) ?? .cpu

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Hero Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(tab.title, systemImage: tab.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(color)

                        Spacer()

                        Picker("Window", selection: $useHourWindow) {
                            Text("5 Min").tag(false)
                            Text("1 Hour").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        BigNumber(value: format(history.latest), unit: "", size: 36)
                        Spacer()
                    }

                    MetricHeroChart(
                        points: history.points(last: windowSecs),
                        color: color,
                        maxValue: tab == .cpu || tab == .memory || tab == .gpu ? 1.0 : nil,
                        formatLabel: format
                    )
                    .frame(height: 180)
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

                // Stats Cards
                HStack(spacing: 12) {
                    statCard(title: "Current", value: format(history.latest), color: color)
                    statCard(title: "Average", value: format(history.average), color: Theme.inkSecondary)
                    statCard(title: "Peak", value: format(history.peak), color: Theme.red)
                }

                // Top Apps Table
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionTitle(title: "Apps using \(tab.title)")
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkSecondary)
                            TextField("Filter...", text: $filter)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11.5))
                                .frame(width: 90)
                            if !filter.isEmpty {
                                Button { filter = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.inkTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border))
                    }
                    AppTable(store: store, primary: primaryMetric, filter: filter)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metricProps(_ sys: SystemStats) -> (MetricHistory, Color, (Double) -> String) {
        switch tab {
        case .cpu:
            return (store.cpuHistory, Theme.cpu, { Format.percent($0) })
        case .memory:
            return (store.memHistory, Theme.memory, { Format.percent($0) })
        case .network:
            return (store.netInHistory, Theme.network, { Format.rate($0) })
        case .disk:
            return (store.diskHistory, Theme.disk, { Format.rate($0) })
        case .gpu:
            return (store.gpuHistory, Theme.gpu, { Format.percent($0) })
        default:
            return (store.cpuHistory, Theme.accent, { Format.percent($0) })
        }
    }
}
