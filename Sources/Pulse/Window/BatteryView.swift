import SwiftUI
import PulseCore

struct BatteryView: View {
    @Bindable var store: AppStore

    var body: some View {
        let bat = store.snapshot.battery ?? defaultBattery()
        let topApp = store.snapshot.apps.first

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: Hero Card (Stats Left + Area Chart Right)
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(bat.isCharging ? "Charging" : (bat.isPluggedIn ? "Fully Charged" : "On battery"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(bat.level)")
                                .font(.system(size: 44, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink)
                            Text("%")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Theme.inkSecondary)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            if let remaining = bat.minutesToEmpty, remaining > 0 {
                                HStack(spacing: 6) {
                                    Text("Remaining")
                                        .foregroundStyle(Theme.inkSecondary)
                                    Text(Format.minutes(remaining))
                                        .font(.system(size: 12, weight: .semibold))
                                        .monospacedDigit()
                                }
                            } else if let toFull = bat.minutesToFull, toFull > 0 {
                                HStack(spacing: 6) {
                                    Text("Until Full")
                                        .foregroundStyle(Theme.inkSecondary)
                                    Text(Format.minutes(toFull))
                                        .font(.system(size: 12, weight: .semibold))
                                        .monospacedDigit()
                                }
                            } else {
                                HStack(spacing: 6) {
                                    Text("Status")
                                        .foregroundStyle(Theme.inkSecondary)
                                    Text(bat.isPluggedIn ? "Power Adapter" : "Normal")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }

                            if let cycles = bat.cycleCount {
                                HStack(spacing: 6) {
                                    Text("Cycles")
                                        .foregroundStyle(Theme.inkSecondary)
                                    Text("\(cycles)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .monospacedDigit()
                                }
                            }
                        }
                        .font(.system(size: 12))
                    }
                    .frame(width: 170, alignment: .leading)

                    // Battery Trend Area Chart
                    MetricHeroChart(
                        points: store.batteryHistory.points(last: 3600),
                        color: Theme.battery,
                        maxValue: 1.0,
                        formatLabel: { Format.percent($0) }
                    )
                    .frame(height: 140)
                }
                .padding(18)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

                // MARK: 4 Breakdown Cards
                HStack(spacing: 12) {
                    // 1. Power Draw
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.battery)
                            Text("Power Draw")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Text(String(format: "%.1f W", abs(bat.watts ?? 10.4)))
                            .font(.system(size: 20, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // 2. Health
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "battery.100")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.battery)
                            Text("Health")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        let health = bat.health ?? 0.99
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Format.percent(health))
                                .font(.system(size: 20, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink)
                            ProgressTrack(value: health, color: Theme.battery)
                                .frame(height: 5)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // 3. Temperature
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "thermometer.medium")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.battery)
                            Text("Temperature")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Text("\(bat.temperature ?? 31)°")
                            .font(.system(size: 20, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // 4. Top App
                    Button {
                        if let topApp { store.selectedAppID = topApp.id }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 5) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.battery)
                                Text("Top App")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Theme.inkSecondary)
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
                                Text(String(format: "%.1f W", max(0.5, topApp.cpu * 0.08)))
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.battery)
                            } else {
                                Text("None")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                // MARK: Top Power Apps Table
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("App")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                        Spacer()
                        Text("Power")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .padding(.horizontal, 14)

                    let apps = Array(store.snapshot.apps.prefix(10))
                    let maxCpu = max(1.0, apps.first?.cpu ?? 1.0)

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
                                    let watts = max(0.2, (app.cpu / maxCpu) * abs(bat.watts ?? 10.4) * 0.7)
                                    InlineBar(value: app.cpu / maxCpu, color: Theme.battery, width: 80)
                                    Text(String(format: "%.1f W", watts))
                                        .font(.system(size: 13, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.ink)
                                        .frame(width: 55, alignment: .trailing)
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
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    private func defaultBattery() -> BatteryInfo {
        var b = BatteryInfo()
        b.level = 100
        b.isPluggedIn = true
        b.health = 1.0
        b.watts = 0.0
        b.temperature = 31
        return b
    }
}
