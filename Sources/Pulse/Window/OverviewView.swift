import SwiftUI
import PulseCore

struct Stat: Identifiable {
    let label: String
    let value: String
    var dot: Color? = nil
    var id: String { label }
}

/// One overview card: header, caption, big number (+pill), three stats, graph at the bottom.
struct MetricCard<Graph: View>: View {
    let tab: PulseTab
    let caption: String
    let value: String
    let unit: String
    var pill: (String, Color, String)? = nil
    let stats: [Stat]
    var action: () -> Void
    @ViewBuilder var graph: Graph

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: tab.title, icon: tab.icon, color: tab.color)
                Text(caption).font(.system(size: 11)).foregroundStyle(Theme.inkSecondary).lineLimit(1).padding(.top, 10)
                HStack(alignment: .firstTextBaseline) {
                    BigNumber(value: value, unit: unit, size: 30)
                    Spacer(minLength: 4)
                    if let pill { Pill(pill.0, color: pill.1, symbol: pill.2) }
                }
                HStack(alignment: .top, spacing: 6) {
                    ForEach(stats) { StatColumn(label: $0.label, value: $0.value, dot: $0.dot) }
                }
                .padding(.top, 6)
                Spacer(minLength: 10)
                graph.frame(height: 34)
            }
            .padding(16)
            .frame(height: 200)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(CardButtonStyle())
    }
}

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct OverviewView: View {
    @Bindable var store: AppStore
    @State private var showAllInsights = false

    private let grid = [GridItem(.adaptive(minimum: 225), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LazyVGrid(columns: grid, spacing: 14) {
                    cpuCard; memoryCard; gpuCard; diskCard
                    networkCard; batteryCard; appsCard; projectsCard
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    memoryByType; memoryByApp; cpuByApp
                }
                .padding(.top, 14)

                if !store.alerts.isEmpty { insights.padding(.top, 26) }

                SectionTitle(title: "Right Now", trailing: "All Apps") { store.activeTab = .apps }
                    .padding(.top, 26).padding(.bottom, 10)
                AppTable(store: store, primary: .cpu, limit: 8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
    }

    private var sys: SystemStats { store.snapshot.system }
    private func go(_ t: PulseTab) { withAnimation(.snappy(duration: 0.22)) { store.activeTab = t } }

    // MARK: Cards

    private var cpuCard: some View {
        MetricCard(tab: .cpu, caption: "Now", value: Format.percentNumber(sys.cpuTotal), unit: "%",
                   stats: [Stat(label: "User", value: Format.percent(sys.cpuUser)),
                           Stat(label: "System", value: Format.percent(sys.cpuSystem)),
                           Stat(label: "Average", value: Format.percent(store.cpuHistory.average))],
                   action: { go(.cpu) }) {
            BarSpark(values: store.cpuHistory.recentValues, color: Theme.cpu, maxValue: 1)
        }
    }

    private var memoryCard: some View {
        let (v, u) = Format.bytesParts(sys.memoryUsed)
        return MetricCard(tab: .memory, caption: "In Use of \(Format.bytes(sys.memoryTotal, compact: true))", value: v, unit: u,
                          pill: pressurePill(sys.pressure),
                          stats: [Stat(label: "App", value: Format.bytes(sys.memoryApp), dot: Theme.cpu),
                                  Stat(label: "Wired", value: Format.bytes(sys.memoryWired), dot: Theme.orange),
                                  Stat(label: "Compressed", value: Format.bytes(sys.memoryCompressed), dot: Theme.network)],
                          action: { go(.memory) }) {
            BarSpark(values: store.memHistory.recentValues, color: Theme.memory, maxValue: 1)
        }
    }

    private var gpuCard: some View {
        let busiest = store.busiest { $0.gpu }
        return MetricCard(tab: .gpu, caption: Hardware.chip, value: sys.gpu.map(Format.percentNumber) ?? "—", unit: "%",
                          stats: [Stat(label: "Average", value: Format.percent(store.gpuHistory.average)),
                                  Stat(label: "Peak", value: Format.percent(store.gpuHistory.peak)),
                                  Stat(label: "Busiest", value: (busiest?.gpu ?? 0) > 0.005 ? busiest!.name : "—")],
                          action: { go(.gpu) }) {
            BarSpark(values: store.gpuHistory.recentValues, color: Theme.gpu, maxValue: 1)
        }
    }

    private var diskCard: some View {
        let (v, u) = Format.bytesParts(sys.diskFree)
        return MetricCard(tab: .disk, caption: "Free of \(Format.bytes(sys.diskTotal, compact: true))", value: v, unit: u,
                          stats: [Stat(label: "Reading", value: Format.rate(sys.diskRead)),
                                  Stat(label: "Writing", value: Format.rate(sys.diskWrite)),
                                  Stat(label: "Written", value: Format.bytes(sys.sessionWritten))],
                          action: { go(.disk) }) {
            BarSpark(values: store.diskHistory.recentValues, color: Theme.disk)
        }
    }

    private var networkCard: some View {
        let (v, u) = Format.rateParts(sys.netIn)
        return MetricCard(tab: .network, caption: "Downloading · \(sys.interfaceName)", value: v, unit: u,
                          stats: [Stat(label: "Uploading", value: Format.rate(sys.netOut)),
                                  Stat(label: "Downloaded", value: Format.bytes(sys.sessionDownloaded)),
                                  Stat(label: "Uploaded", value: Format.bytes(sys.sessionUploaded))],
                          action: { go(.network) }) {
            BarSpark(values: store.netInHistory.recentValues, color: Theme.network)
        }
    }

    @ViewBuilder private var batteryCard: some View {
        if let b = store.snapshot.battery {
            let state = b.isCharging ? "Charging" : (b.isPluggedIn ? "On Power Adapter" : "On Battery")
            let remaining = b.isCharging ? b.minutesToFull.map(Format.minutes) : b.minutesToEmpty.map(Format.minutes)
            MetricCard(tab: .battery, caption: state, value: "\(b.level)", unit: "%",
                       stats: [Stat(label: b.isCharging ? "Until Full" : "Remaining", value: remaining ?? "—"),
                               Stat(label: "Power Draw", value: b.watts.map { String(format: "%.1f W", abs($0)) } ?? "—"),
                               Stat(label: "Health", value: b.health.map(Format.percent) ?? "—")],
                       action: { go(.battery) }) {
                BarSpark(values: store.batteryHistory.recentValues, color: Theme.battery, maxValue: 1)
            }
        } else {
            MetricCard(tab: .battery, caption: "Desktop Mac", value: "AC", unit: "",
                       stats: [Stat(label: "Source", value: "Power Adapter")], action: { go(.battery) }) {
                ProgressTrack(value: 1, color: Theme.battery)
            }
        }
    }

    private var appsCard: some View {
        let top = Array(store.snapshot.apps.sorted { $0.memory > $1.memory }.prefix(3))
        return MetricCard(tab: .apps, caption: "Running now", value: "\(store.snapshot.apps.count)", unit: "apps",
                          stats: [Stat(label: "Processes", value: store.snapshot.processCount.formatted()),
                                  Stat(label: "Heaviest", value: top.first?.name ?? "—")],
                          action: { go(.apps) }) {
            HStack(spacing: 10) {
                ForEach(top) { a in
                    HStack(spacing: 5) {
                        AppIconView(app: a, size: 16)
                        Text(Format.bytes(a.memory, compact: true)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Theme.inkSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .background(Theme.apps.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private var projectsCard: some View {
        let d = store.dev
        let mem = d.projects.reduce(UInt64(0)) { $0 + $1.memory }
        return MetricCard(tab: .projects, caption: "\(d.ports.filter { !$0.isDynamic }.count) ports open", value: "\(d.projects.count)",
                          unit: d.projects.count == 1 ? "project" : "projects",
                          pill: d.idleServers.isEmpty ? nil : ("\(d.idleServers.count) idle", Theme.projects, "moon.zzz.fill"),
                          stats: [Stat(label: "Memory", value: Format.bytes(mem)),
                                  Stat(label: "Largest", value: d.projects.first?.name ?? "—")],
                          action: { go(.projects) }) {
            HStack(spacing: 6) {
                ForEach(d.projects.prefix(3)) { p in
                    Text(p.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.projects).lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.projects.opacity(0.12), in: Capsule())
                }
                if d.projects.isEmpty {
                    Text("Nothing running in a project folder").font(.system(size: 11)).foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .background(Theme.projects.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    // MARK: Donuts

    private var memoryByType: some View {
        let total = Double(max(sys.memoryTotal, 1))
        let free = sys.memoryTotal > sys.memoryUsed + sys.memoryCached ? sys.memoryTotal - sys.memoryUsed - sys.memoryCached : 0
        let segs = [
            DonutSegment(id: "app", label: "App", value: Double(sys.memoryApp), color: Theme.cpu, detail: Format.bytes(sys.memoryApp)),
            DonutSegment(id: "wired", label: "Wired", value: Double(sys.memoryWired), color: Theme.orange, detail: Format.bytes(sys.memoryWired)),
            DonutSegment(id: "comp", label: "Compressed", value: Double(sys.memoryCompressed), color: Theme.network, detail: Format.bytes(sys.memoryCompressed)),
            DonutSegment(id: "cached", label: "Cached", value: Double(sys.memoryCached), color: Theme.inkTertiary, detail: Format.bytes(sys.memoryCached)),
            DonutSegment(id: "free", label: "Free", value: Double(free), color: Theme.inkTertiary.opacity(0.35), detail: Format.bytes(free)),
        ]
        return DonutCard(title: "Memory by Type", icon: "memorychip", color: Theme.memory, segments: segs,
                         centerValue: Format.percent(Double(sys.memoryUsed) / total), centerCaption: "in use")
    }

    private var memoryByApp: some View {
        let palette = [Theme.memory, Theme.memory.opacity(0.75), Theme.memory.opacity(0.55), Theme.memory.opacity(0.38)]
        let apps = store.snapshot.apps.filter { $0.kind != .system }.sorted { $0.memory > $1.memory }
        let top = Array(apps.prefix(4))
        let rest = apps.dropFirst(4).reduce(UInt64(0)) { $0 + $1.memory }
        var segs = top.enumerated().map { i, a in
            DonutSegment(id: a.id, label: a.name, value: Double(a.memory), color: palette[i], detail: Format.bytes(a.memory))
        }
        segs.append(DonutSegment(id: "other", label: "Other", value: Double(rest), color: Theme.inkTertiary.opacity(0.35), detail: Format.bytes(rest)))
        let total = apps.reduce(UInt64(0)) { $0 + $1.memory }
        return DonutCard(title: "Memory by App", icon: "square.stack", color: Theme.memory, segments: segs,
                         centerValue: Format.bytes(total, compact: true), centerCaption: "all apps",
                         appIcons: Dictionary(uniqueKeysWithValues: top.map { ($0.id, $0) }))
    }

    private var cpuByApp: some View {
        let palette = [Theme.cpu, Theme.cpu.opacity(0.75), Theme.cpu.opacity(0.55), Theme.cpu.opacity(0.38)]
        let apps = store.snapshot.apps.sorted { $0.cpu > $1.cpu }
        let top = Array(apps.prefix(4))
        let rest = apps.dropFirst(4).reduce(0.0) { $0 + $1.cpu }
        var segs = top.enumerated().map { i, a in
            DonutSegment(id: a.id, label: a.name, value: a.cpu, color: palette[i], detail: Format.cpuShare(a.cpu))
        }
        segs.append(DonutSegment(id: "other", label: "Other", value: rest, color: Theme.inkTertiary.opacity(0.35), detail: Format.cpuShare(rest)))
        return DonutCard(title: "CPU by App", icon: "cpu", color: Theme.cpu, segments: segs,
                         centerValue: Format.percent(sys.cpuTotal), centerCaption: "total",
                         appIcons: Dictionary(uniqueKeysWithValues: top.map { ($0.id, $0) }))
    }

    // MARK: Insights

    private var insights: some View {
        let list = showAllInsights ? store.alerts : Array(store.alerts.prefix(3))
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Worth a Look",
                         trailing: store.alerts.count > 3 ? (showAllInsights ? "Show Less" : "Show All \(store.alerts.count)") : nil) {
                showAllInsights.toggle()
            }
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                    InsightRow(alert: a, store: store)
                    if i < list.count - 1 { Divider().padding(.leading, 58) }
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
    }
}

func pressurePill(_ p: MemoryPressure) -> (String, Color, String) {
    switch p {
    case .normal: ("Normal", Theme.green, "checkmark")
    case .warning: ("Elevated", Theme.orange, "exclamationmark")
    case .critical: ("Critical", Theme.red, "exclamationmark.triangle.fill")
    }
}

struct InsightRow: View {
    let alert: PulseAlert
    let store: AppStore

    var body: some View {
        let (label, color) = kindStyle
        HStack(spacing: 12) {
            Group {
                if let app = store.app(alert.appID) { AppIconView(app: app, size: 28) }
                else { IconTile(symbol: alert.kind == .memoryPressure ? "memorychip" : "waveform.path.ecg", color: color, size: 28) }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(alert.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    if alert.count > 1 {
                        Text("\(alert.count)×").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(Theme.ink.opacity(0.07), in: Capsule())
                    }
                }
                Text(alert.detail).font(.system(size: 12)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
            }
            Spacer()
            Pill(label, color: color)
            Text(alert.date, format: .relative(presentation: .named))
                .font(.system(size: 11.5)).foregroundStyle(Theme.inkTertiary).frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .contentShape(Rectangle())
        .onTapGesture { if let id = alert.appID { store.selectedAppID = id } }
    }

    private var kindStyle: (String, Color) {
        switch alert.kind {
        case .sustainedCPU: ("CPU", Theme.cpu)
        case .memoryGrowth, .memoryPressure: ("Memory", Theme.memory)
        case .idleServer: ("Projects", Theme.projects)
        case .networkBurst: ("Network", Theme.network)
        case .diskBurst: ("Disk", Theme.disk)
        }
    }
}
