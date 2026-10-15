import SwiftUI
import PulseCore

struct ProjectsView: View {
    @Bindable var store: AppStore

    var body: some View {
        let dev = store.dev

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Idle Dev Servers Notification Banner
                if !dev.idleServers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("\(dev.idleServers.count) Idle Dev Servers", systemImage: "moon.zzz.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.projects)
                            Spacer()
                            Button("Stop All Idle") {
                                for s in dev.idleServers {
                                    _ = ProcessActions.terminate(pid: s.pid, force: false)
                                }
                            }
                            .controlSize(.small)
                        }

                        ForEach(dev.idleServers) { s in
                            HStack {
                                Text(s.name)
                                    .font(.system(size: 12.5, weight: .medium))
                                Text("Ports: \(s.ports.map(String.init).joined(separator: ", "))")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.inkSecondary)
                                Spacer()
                                Text("Idle \(Format.duration(s.idleFor))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.inkTertiary)
                                Button("Stop") {
                                    _ = ProcessActions.terminate(pid: s.pid, force: false)
                                }
                                .controlSize(.mini)
                            }
                            .padding(8)
                            .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(14)
                    .background(Theme.projects.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Active Dev Projects
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Active Projects (\(dev.projects.count))")

                    if dev.projects.isEmpty {
                        PulseCard {
                            Text("No developer processes detected running inside project folders.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    } else {
                        VStack(spacing: 8) {
                            ForEach(dev.projects) { proj in
                                HStack {
                                    IconTile(symbol: "folder.fill", color: Theme.projects, size: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(proj.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Theme.ink)
                                        Text("\(proj.pids.count) processes · CPU \(Format.cpuShare(proj.cpu))")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.inkSecondary)
                                    }
                                    Spacer()
                                    if !proj.ports.isEmpty {
                                        Text("Ports: \(proj.ports.map(String.init).joined(separator: ", "))")
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundStyle(Theme.projects)
                                            .padding(.trailing, 8)
                                    }
                                    Text(Format.bytes(proj.memory, compact: true))
                                        .font(.system(size: 13, weight: .semibold))
                                        .monospacedDigit()
                                }
                                .padding(12)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }

                // Open Ports
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Open TCP Ports (\(dev.ports.count))")

                    VStack(spacing: 0) {
                        ForEach(Array(dev.ports.enumerated()), id: \.element.id) { idx, lp in
                            HStack {
                                Text(":\(lp.port)")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 60, alignment: .leading)
                                Text(lp.processName)
                                    .font(.system(size: 12.5))
                                    .lineLimit(1)
                                Spacer()
                                Text("PID \(lp.pid)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.inkTertiary)
                                if !lp.isDynamic {
                                    Button {
                                        if let url = URL(string: "http://localhost:\(lp.port)") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    } label: {
                                        Image(systemName: "safari")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.accent)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Open in Browser")
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)

                            if idx < dev.ports.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Sleep Blockers
                if !dev.blockers.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "Keeping This Mac Awake (\(dev.blockers.count))")

                        VStack(spacing: 8) {
                            ForEach(dev.blockers) { b in
                                HStack {
                                    IconTile(symbol: b.kind == .display ? "display" : "cup.and.saucer.fill", color: Theme.disk, size: 24)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(b.processName)
                                            .font(.system(size: 12.5, weight: .medium))
                                        Text(b.reason)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.inkSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Pill(b.kind == .display ? "Screen On" : "Mac Awake", color: Theme.disk)
                                }
                                .padding(10)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
    }
}
