import SwiftUI
import PulseCore

struct MenuBarPanelView: View {
    @Bindable var store: AppStore
    @Environment(\.openWindow) var openWindow

    var body: some View {
        let sys = store.snapshot.system

        VStack(alignment: .leading, spacing: 12) {
            // Header: Mac title & uptime
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text("OVERVIEW")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text("Up \(Format.duration(Hardware.uptime))")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, 4)

            // Grid of 6 mini metric cards with BarSparks
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                miniCard(
                    title: "CPU",
                    value: Format.percent(sys.cpuTotal),
                    caption: "load \(String(format: "%.1f", sys.loadAverage))",
                    color: Theme.cpu
                ) {
                    LineSpark(values: store.cpuHistory.recentValues, color: Theme.cpu, maxValue: 1.0)
                }

                let (mVal, mUnit) = Format.bytesParts(sys.memoryUsed)
                miniCard(
                    title: "Memory",
                    value: "\(mVal) \(mUnit)",
                    caption: "of \(Format.bytes(sys.memoryTotal, compact: true))",
                    color: Theme.memory
                ) {
                    LineSpark(values: store.memHistory.recentValues, color: Theme.memory, maxValue: 1.0)
                }

                let (dVal, dUnit) = Format.rateParts(sys.netIn)
                miniCard(
                    title: "Network",
                    value: "\(dVal) \(dUnit)",
                    caption: "↑ \(Format.rate(sys.netOut))",
                    color: Theme.network
                ) {
                    LineSpark(values: store.netInHistory.recentValues, color: Theme.network)
                }

                let (fVal, fUnit) = Format.bytesParts(sys.diskFree)
                miniCard(
                    title: "Disk Free",
                    value: "\(fVal) \(fUnit)",
                    caption: "\(Int(sys.diskUsedFraction * 100))% used",
                    color: Theme.disk
                ) {
                    ProgressTrack(value: sys.diskUsedFraction, color: Theme.disk, height: 5)
                }

                miniCard(
                    title: "GPU",
                    value: sys.gpu.map { Format.percent($0) } ?? "—",
                    caption: "Metal",
                    color: Theme.gpu
                ) {
                    LineSpark(values: store.gpuHistory.recentValues, color: Theme.gpu, maxValue: 1.0)
                }

                if let bat = store.snapshot.battery {
                    miniCard(
                        title: "Battery",
                        value: "\(bat.level)%",
                        caption: bat.isCharging ? "Charging" : (bat.minutesToEmpty.map { Format.minutes($0) } ?? "On battery"),
                        color: Theme.battery
                    ) {
                        ProgressTrack(value: Double(bat.level) / 100.0, color: Theme.battery, height: 5)
                    }
                }
            }

            // Busiest Right Now (Top Apps with progress bars)
            VStack(alignment: .leading, spacing: 8) {
                Text("Busiest Right Now")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)

                let top = Array(store.snapshot.apps.prefix(4))
                let maxCPU = max(top.first?.cpu ?? 1.0, 1.0)

                ForEach(top) { app in
                    HStack(spacing: 8) {
                        AppIconView(app: app, size: 16)
                        Text(app.name)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        InlineBar(value: app.cpu / maxCPU, color: Theme.accent, width: 60, height: 5)
                        Text(Format.cpuShare(app.cpu))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                            .frame(width: 48, alignment: .trailing)
                    }
                    .frame(height: 22)
                }
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Footer
            HStack(spacing: 8) {
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "macwindow")
                        Text("Open Pulse")
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    NSApp.terminate(nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                        Text("Quit")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .controlSize(.regular)
            }
        }
        .padding(14)
        .frame(width: 370)
        .background(Theme.bg)
    }

    private func miniCard<V: View>(title: String, value: String, caption: String, color: Color, @ViewBuilder visual: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline) {
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
                Spacer(minLength: 2)
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            visual()
                .frame(height: 20)
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
