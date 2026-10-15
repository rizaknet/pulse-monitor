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
        let topApp = store.snapshot.apps.first

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: Hero Card (Stats Left + Line Chart Right)
                heroSection(sys: sys, history: history, color: color, format: format, windowSecs: windowSecs)

                // MARK: 4 Meaningful Breakdown Cards
                breakdownCards(sys: sys, color: color, topApp: topApp)

                // MARK: Top Apps Table
                appsSection(primaryMetric: primaryMetric)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Hero Section

    @ViewBuilder
    private func heroSection(sys: SystemStats, history: MetricHistory, color: Color, format: @escaping (Double) -> String, windowSecs: TimeInterval) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                switch tab {
                case .cpu:
                    Text("Now")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Format.percentNumber(sys.cpuTotal))
                            .font(.system(size: 44, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                        Text("%")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Average today")
                                .foregroundStyle(Theme.inkSecondary)
                            Text(Format.percent(store.cpuHistory.average))
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                        }
                        HStack(spacing: 6) {
                            Text("Load")
                                .foregroundStyle(Theme.inkSecondary)
                            Text(String(format: "%.2f", sys.loadAverage))
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 12))

                case .memory:
                    Text("In use of \(Format.bytes(sys.memoryTotal, compact: true))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        let (v, u) = Format.bytesParts(sys.memoryUsed)
                        Text(v)
                            .font(.system(size: 44, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                        Text(u)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.inkSecondary)
                        Pill(
                            sys.pressure.label,
                            color: sys.pressure == .critical ? Theme.red : (sys.pressure == .warning ? Theme.orange : Theme.green),
                            symbol: sys.pressure == .normal ? "checkmark" : "exclamationmark.triangle"
                        )
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Free")
                                .foregroundStyle(Theme.inkSecondary)
                            Text(Format.bytes(sys.memoryTotal > sys.memoryUsed ? sys.memoryTotal - sys.memoryUsed : 0))
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                        }
                        HStack(spacing: 6) {
                            Text("Swap")
                                .foregroundStyle(Theme.inkSecondary)
                            Text(Format.bytes(sys.swapUsed))
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 12))

                case .disk:
                    Text("Disk Activity")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                    let totalRate = sys.diskRead + sys.diskWrite
                    let (v, u) = Format.rateParts(totalRate)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(v)
                            .font(.system(size: 40, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                        Text(u)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Total Read")
                                .foregroundStyle(Theme.inkSecondary)
                            Text(Format.bytes(sys.sessionRead))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        HStack(spacing: 6) {
                            Text("Total Written")
                                .foregroundStyle(Theme.inkSecondary)
                            Text(Format.bytes(sys.sessionWritten))
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .font(.system(size: 12))

                case .network:
                    Text("Downloading · \(sys.interfaceName)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                    let (v, u) = Format.rateParts(sys.netIn)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(v)
                            .font(.system(size: 40, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                        Text(u)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Downloaded")
                                .foregroundStyle(Theme.inkSecondary)
                            Text(Format.bytes(sys.sessionDownloaded))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        HStack(spacing: 6) {
                            Text("Uploaded")
                                .foregroundStyle(Theme.inkSecondary)
                            Text(Format.bytes(sys.sessionUploaded))
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .font(.system(size: 12))

                default:
                    Text("Now")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(format(history.latest))
                            .font(.system(size: 44, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Average")
                                .foregroundStyle(Theme.inkSecondary)
                            Text(format(history.average))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        HStack(spacing: 6) {
                            Text("Peak")
                                .foregroundStyle(Theme.inkSecondary)
                            Text(format(history.peak))
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .font(.system(size: 12))
                }
            }
            .frame(width: 190, alignment: .leading)

            // Right side area line chart
            MetricHeroChart(
                points: history.points(last: windowSecs),
                color: color,
                maxValue: tab == .cpu || tab == .memory || tab == .gpu ? 1.0 : nil,
                formatLabel: format
            )
            .frame(height: 140)
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    // MARK: - 4 Meaningful Breakdown Cards

    @ViewBuilder
    private func breakdownCards(sys: SystemStats, color: Color, topApp: AppUsage?) -> some View {
        HStack(spacing: 12) {
            switch tab {
            case .cpu:
                // 1. User
                breakdownTile(title: "User", icon: "person.fill", value: Format.percent(sys.cpuUser), caption: "Your apps", color: color)
                // 2. System
                breakdownTile(title: "System", icon: "apple.logo", value: Format.percent(sys.cpuSystem), caption: "macOS", color: color)
                // 3. Cores
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                        Text("Cores").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(Hardware.cores)")
                            .font(.system(size: 20, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                        let p = Hardware.performanceCores > 0 ? Hardware.performanceCores : 4
                        let e = Hardware.efficiencyCores > 0 ? Hardware.efficiencyCores : 6
                        Pill("\(p) P", color: color)
                        Pill("\(e) E", color: Theme.inkSecondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                // 4. Top App
                topAppTile(topApp: topApp, value: Format.percent(topApp?.cpu ?? 0), color: color)

            case .memory:
                // 1. App
                progressTile(title: "App", icon: "square.stack", value: Format.bytes(sys.memoryApp), frac: Double(sys.memoryApp) / Double(max(1, sys.memoryTotal)), color: color)
                // 2. Wired
                progressTile(title: "Wired", icon: "lock.fill", value: Format.bytes(sys.memoryWired), frac: Double(sys.memoryWired) / Double(max(1, sys.memoryTotal)), color: Theme.orange)
                // 3. Compressed
                progressTile(title: "Compressed", icon: "arrow.down.right.and.arrow.up.left", value: Format.bytes(sys.memoryCompressed), frac: Double(sys.memoryCompressed) / Double(max(1, sys.memoryTotal)), color: Theme.green)
                // 4. Top App
                topAppTile(topApp: topApp, value: Format.bytes(topApp?.memory ?? 0), color: color)

            case .disk:
                // 1. Read
                breakdownTile(title: "Reading", icon: "arrow.down", value: Format.rate(sys.diskRead), caption: "From SSD", color: color)
                // 2. Write
                breakdownTile(title: "Writing", icon: "arrow.up", value: Format.rate(sys.diskWrite), caption: "To SSD", color: color)
                // 3. Free
                breakdownTile(title: "Free of \(Format.bytes(sys.diskTotal, compact: true))", icon: "internaldrive", value: Format.bytes(sys.diskFree), caption: "\(Int(sys.diskUsedFraction * 100))% used", color: color)
                // 4. Top App
                topAppTile(topApp: topApp, value: Format.rate(topApp?.diskIO ?? 0), color: color)

            case .network:
                // 1. Download
                breakdownTile(title: "Download", icon: "arrow.down.circle", value: Format.rate(sys.netIn), caption: "Incoming", color: color)
                // 2. Upload
                breakdownTile(title: "Upload", icon: "arrow.up.circle", value: Format.rate(sys.netOut), caption: "Outgoing", color: color)
                // 3. Interface
                breakdownTile(title: "Interface", icon: "wifi", value: sys.interfaceName, caption: "Primary", color: color)
                // 4. Top App
                topAppTile(topApp: topApp, value: Format.rate(topApp?.network ?? 0), color: color)

            default:
                // GPU
                breakdownTile(title: "Renderer", icon: "cpu", value: "Apple M5", caption: "Metal GPU", color: color)
                breakdownTile(title: "Active", icon: "play.fill", value: Format.percent(sys.gpu ?? 0), caption: "Compute", color: color)
                breakdownTile(title: "Display", icon: "display", value: "120 Hz", caption: "ProMotion", color: color)
                topAppTile(topApp: topApp, value: Format.percent(topApp?.gpu ?? 0), color: color)
            }
        }
    }

    // MARK: - Tile Helpers

    private func breakdownTile(title: String, icon: String, value: String, caption: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func progressTile(title: String, icon: String, value: String, frac: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            ProgressTrack(value: frac, color: color)
                .frame(height: 5)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func topAppTile(topApp: AppUsage?, value: String, color: Color) -> some View {
        Button {
            if let topApp { store.selectedAppID = topApp.id }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                    Text("Top App").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                }
                if let topApp {
                    HStack(spacing: 8) {
                        if let bp = topApp.bundlePath {
                            Image(nsImage: IconCache.icon(forPath: bp))
                                .resizable()
                                .frame(width: 20, height: 20)
                        }
                        Text(topApp.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    Text(value)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(color)
                } else {
                    Text("None").font(.system(size: 14)).foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Apps Table Section

    private func appsSection(primaryMetric: AppMetric) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("App")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
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

                Text(primaryMetric.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 14)

            let filtered = store.snapshot.apps.filter {
                filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter)
            }
            let apps = Array(filtered.prefix(12))
            let maxVal = max(0.001, apps.map { primaryMetric.value($0) }.max() ?? 1.0)

            VStack(spacing: 0) {
                ForEach(apps) { app in
                    HStack(spacing: 12) {
                        if let bp = app.bundlePath {
                            Image(nsImage: IconCache.icon(forPath: bp))
                                .resizable()
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "app.fill")
                                .font(.system(size: 20))
                                .frame(width: 24, height: 24)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text("\(app.processes.count) processes")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkSecondary)
                        }

                        Spacer()

                        HStack(spacing: 12) {
                            let val = primaryMetric.value(app)
                            InlineBar(value: val / maxVal, color: primaryMetric.color, width: 100)
                            Text(primaryMetric.format(val))
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink)
                                .frame(width: 65, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.selectedAppID = app.id
                    }
                    if app.id != apps.last?.id {
                        Divider().opacity(0.3)
                    }
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
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
