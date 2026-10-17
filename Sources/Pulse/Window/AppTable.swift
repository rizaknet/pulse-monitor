import SwiftUI
import PulseCore

/// A per-app metric (column) that tables can show, sort and bar-chart.
enum AppMetric: String, CaseIterable, Identifiable {
    case cpu, memory, gpu, network, disk
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .network: "Network"
        case .disk: "Disk"
        }
    }

    var color: Color {
        switch self {
        case .cpu: Theme.cpu
        case .memory: Theme.memory
        case .gpu: Theme.gpu
        case .network: Theme.network
        case .disk: Theme.disk
        }
    }

    func value(_ a: AppUsage) -> Double {
        switch self {
        case .cpu: a.cpu
        case .memory: Double(a.memory)
        case .gpu: a.gpu
        case .network: a.network
        case .disk: a.diskIO
        }
    }

    func value(_ p: ProcessUsage) -> Double {
        switch self {
        case .cpu: p.cpu
        case .memory: Double(p.memory)
        case .gpu: p.gpu
        case .network: p.netIn + p.netOut
        case .disk: p.diskRead + p.diskWrite
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .cpu: Format.cpuShare(v)
        case .memory: Format.bytes(UInt64(max(v, 0)))
        case .gpu: v > 0.0005 ? String(format: "%.1f%%", v * 100) : "—"
        case .network, .disk: v >= 1 ? Format.rate(v) : "—"
        }
    }

    /// The other columns shown next to this one.
    var companions: [AppMetric] {
        switch self {
        case .cpu: [.memory, .gpu, .network]
        case .memory: [.cpu, .gpu, .network]
        case .gpu: [.cpu, .memory]
        case .network: [.cpu, .memory]
        case .disk: [.cpu, .memory]
        }
    }

    init?(tab: PulseTab) {
        switch tab {
        case .cpu: self = .cpu
        case .memory: self = .memory
        case .gpu: self = .gpu
        case .network: self = .network
        case .disk: self = .disk
        default: return nil
        }
    }
}

struct AppTable: View {
    @Bindable var store: AppStore
    let primary: AppMetric
    var filter = ""
    var limit: Int? = nil
    var showDescription: Bool = false

    @State private var sortKey: String? = nil      // nil = primary metric
    @State private var ascending = false
    @State private var expanded: Set<String> = []
    @State private var pendingQuit: (app: AppUsage, force: Bool)?

    private var columns: [AppMetric] { [primary] + primary.companions }

    var body: some View {
        let key = sortKey ?? primary.rawValue
        let rows = sortedRows(key: key)
        let maxPrimary = max(store.snapshot.apps.map(primary.value).max() ?? 1, 1e-9)

        VStack(spacing: 0) {
            header(key: key)
            Divider().opacity(0.6)
            LazyVStack(spacing: 0) {
                ForEach(rows) { app in
                    row(app, maxPrimary: maxPrimary)
                    if expanded.contains(app.id) { processRows(app) }
                }
            }
            .padding(.vertical, 4)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .confirmationDialog(quitTitle, isPresented: Binding(get: { pendingQuit != nil }, set: { if !$0 { pendingQuit = nil } }),
                            titleVisibility: .visible) {
            Button(pendingQuit?.force == true ? "Force Quit" : "Quit", role: .destructive) {
                if let p = pendingQuit { store.terminate(app: p.app, force: p.force) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let p = pendingQuit {
                Text(p.force ? "\(p.app.name) ends at once. Unsaved changes will be lost."
                             : "\(p.app.processes.count) process\(p.app.processes.count == 1 ? "" : "es") will close. The app can ask to save first.")
            }
        }
    }

    private var quitTitle: String {
        guard let p = pendingQuit else { return "" }
        return "\(p.force ? "Force Quit" : "Quit") \(p.app.name)?"
    }

    private func sortedRows(key: String) -> [AppUsage] {
        var list = store.snapshot.apps
        if !filter.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(filter) } }
        let metric = AppMetric(rawValue: key)
        list.sort { a, b in
            let lt: Bool
            if key == "name" { lt = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
            else if key == "procs" { lt = a.processes.count < b.processes.count }
            else if let metric { lt = metric.value(a) < metric.value(b) }
            else { lt = false }
            return ascending ? lt : !lt
        }
        if let limit { return Array(list.prefix(limit)) }
        return list
    }

    // MARK: Header

    private func header(key: String) -> some View {
        HStack(spacing: 0) {
            if showDescription {
                headerCell("Name", id: "name", key: key, align: .leading)
                    .frame(width: 220, alignment: .leading)
                    .padding(.leading, 52)
                headerCell("AI Description & Legitimacy", id: "desc", key: key, align: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(columns) { c in
                    headerCell(c.title, id: c.rawValue, key: key, align: .trailing)
                        .frame(width: c == primary ? 140 : 86, alignment: .trailing)
                }
            } else {
                headerCell("Name", id: "name", key: key, align: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 52)
                ForEach(columns) { c in
                    headerCell(c.title, id: c.rawValue, key: key, align: .trailing)
                        .frame(width: c == primary ? 170 : 92, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
    }

    private func headerCell(_ title: String, id: String, key: String, align: Alignment) -> some View {
        Button {
            if key == id { ascending.toggle() } else { sortKey = id; ascending = id == "name" }
        } label: {
            HStack(spacing: 3) {
                Text(title).font(.system(size: 11.5, weight: key == id ? .semibold : .medium))
                if key == id {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 7.5, weight: .bold))
                }
            }
            .foregroundStyle(key == id ? Theme.ink : Theme.inkSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Rows

    private func row(_ app: AppUsage, maxPrimary: Double) -> some View {
        let isOpen = expanded.contains(app.id)
        let isSelected = store.selectedAppID == app.id
        return HStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    if isOpen { expanded.remove(app.id) } else { expanded.insert(app.id) }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.inkTertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 18, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(app.processes.count > 1 ? 1 : 0)
            .disabled(app.processes.count <= 1)

            AppIconView(app: app, size: 26).padding(.leading, 4).padding(.trailing, 10)

            if showDescription {
                let intel = AppIntelligence.shared.lookup(app: app)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text("\(app.processes.count) process\(app.processes.count == 1 ? "" : "es")")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSecondary)
                }
                .frame(width: 170, alignment: .leading)

                // AI Description & Legitimacy status column
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: intel.legitimacy.icon)
                            .font(.system(size: 9.5, weight: .bold))
                        Text(intel.legitimacy.title)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(intel.legitimacy.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(intel.legitimacy.badgeBackground, in: Capsule())
                    .overlay(Capsule().stroke(intel.legitimacy.color.opacity(0.25), lineWidth: 1))

                    Text(intel.summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            store.selectedAppID = app.id
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9.5))
                            Text("Inspect")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Theme.agents)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.agents.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("AI deep research & security audit for \(app.name)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(columns) { c in
                    let v = c.value(app)
                    HStack(spacing: 8) {
                        if c == primary { InlineBar(value: v / maxPrimary, color: c.color, width: 44) }
                        Text(c.format(v))
                            .font(.system(size: c == primary ? 12.5 : 12, weight: c == primary ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(c == primary ? Theme.ink : Theme.inkSecondary)
                    }
                    .frame(width: c == primary ? 140 : 86, alignment: .trailing)
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text("\(app.processes.count) process\(app.processes.count == 1 ? "" : "es")")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 8)

                ForEach(columns) { c in
                    let v = c.value(app)
                    HStack(spacing: 10) {
                        if c == primary { InlineBar(value: v / maxPrimary, color: c.color, width: 60) }
                        Text(c.format(v))
                            .font(.system(size: c == primary ? 13 : 12.5, weight: c == primary ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(c == primary ? Theme.ink : Theme.inkSecondary)
                    }
                    .frame(width: c == primary ? 170 : 92, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(isSelected ? Theme.accent.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .hoverHighlight()
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) { store.selectedAppID = isSelected ? nil : app.id }
        }
        .contextMenu { menu(app) }
    }

    @ViewBuilder private func menu(_ app: AppUsage) -> some View {
        Button("AI Deep Inspect") { store.selectedAppID = app.id }
        Button("Show Details") { store.selectedAppID = app.id }
        if app.kind != .system {
            Divider()
            Button("Quit \(app.name)…") { pendingQuit = (app, false) }
            Button("Force Quit \(app.name)…") { pendingQuit = (app, true) }
        }
        Divider()
        if let b = app.bundlePath {
            Button("Reveal in Finder") { NSWorkspace.shared.selectFile(b, inFileViewerRootedAtPath: "") }
        }
        Button("Copy Name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(app.name, forType: .string)
        }
    }

    private func processRows(_ app: AppUsage) -> some View {
        let procs = app.processes.sorted { primary.value($0) > primary.value($1) }.prefix(50)
        return VStack(spacing: 0) {
            ForEach(Array(procs)) { p in
                HStack(spacing: 0) {
                    Text(p.name).font(.system(size: 12)).foregroundStyle(Theme.ink).lineLimit(1)
                        .padding(.leading, 70)
                    Text("  \(p.pid)").font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.inkTertiary)
                    Spacer(minLength: 8)
                    ForEach(columns) { c in
                        Text(p.measured || c == .gpu || c == .network ? c.format(c.value(p)) : "—")
                            .font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.inkSecondary)
                            .frame(width: showDescription ? (c == primary ? 140 : 86) : (c == primary ? 170 : 92), alignment: .trailing)
                    }
                }
                .padding(.horizontal, 18)
                .frame(height: 26)
                .contextMenu {
                    Button("Quit Process") { store.terminate(pid: p.pid, force: false) }
                    Button("Force Quit Process") { store.terminate(pid: p.pid, force: true) }
                    Divider()
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(p.path, forType: .string)
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }
}
