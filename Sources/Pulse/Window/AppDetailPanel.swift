import SwiftUI
import Charts
import PulseCore

struct AppDetailPanel: View {
    let app: AppUsage
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                AppIconView(app: app, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(app.kind == .app ? (app.bundlePath ?? "Application") : "Command Line Tool")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    store.selectedAppID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider().opacity(0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Quick Stats Cards
                    VStack(spacing: 8) {
                        metricRow("CPU", Format.cpuShare(app.cpu), color: Theme.cpu)
                        metricRow("Memory", Format.bytes(app.memory), color: Theme.memory)
                        metricRow("GPU", app.gpu > 0.005 ? Format.percent(app.gpu) : "—", color: Theme.gpu)
                        metricRow("Network", app.network > 100 ? Format.rate(app.network) : "Idle", color: Theme.network)
                        metricRow("Disk I/O", app.diskIO > 100 ? Format.rate(app.diskIO) : "Idle", color: Theme.disk)
                    }
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Sub-processes list
                    Text("Processes (\(app.processes.count))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 4)

                    VStack(spacing: 4) {
                        ForEach(app.processes.sorted { $0.cpu > $1.cpu }) { p in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                    Text("PID \(p.pid)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.inkTertiary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(Format.cpuShare(p.cpu))
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.cpu)
                                    Text(Format.bytes(p.memory, compact: true))
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.inkSecondary)
                                }
                            }
                            .padding(8)
                            .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .padding(16)
            }

            Divider().opacity(0.6)

            // Bottom Actions
            HStack(spacing: 8) {
                Button("Quit App") {
                    store.terminate(app: app, force: false)
                }
                .controlSize(.regular)
                .frame(maxWidth: .infinity)

                Button("Force Quit") {
                    store.terminate(app: app, force: true)
                }
                .controlSize(.regular)
                .frame(maxWidth: .infinity)
            }
            .padding(14)
            .background(Theme.bg)
        }
        .background(Theme.bg)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: -4, y: 0)
    }

    private func metricRow(_ title: String, _ val: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text(val)
                .font(.system(size: 12.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }
}
