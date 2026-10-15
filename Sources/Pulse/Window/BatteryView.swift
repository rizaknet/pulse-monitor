import SwiftUI
import PulseCore

struct BatteryView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let bat = store.snapshot.battery {
                    // Battery level hero card
                    HStack(spacing: 24) {
                        Image(systemName: bat.isCharging ? "bolt.batteryblock.fill" : "batteryblock.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(bat.level > 20 ? Theme.battery : Theme.red)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                BigNumber(value: "\(bat.level)", unit: "%", size: 38)
                                Pill(
                                    bat.isCharging ? "Charging" : (bat.isPluggedIn ? "Fully Charged" : "On Battery"),
                                    color: Theme.battery
                                )
                            }
                            if let remaining = bat.minutesToEmpty {
                                Text("\(Format.minutes(remaining)) remaining until empty")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.inkSecondary)
                            } else if let toFull = bat.minutesToFull {
                                Text("\(Format.minutes(toFull)) until fully charged")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(20)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

                    // Diagnostic Details
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        if let cycles = bat.cycleCount {
                            infoTile(title: "Cycle Count", value: "\(cycles)")
                        }
                        if let health = bat.health {
                            infoTile(title: "Maximum Capacity (Health)", value: Format.percent(health))
                        }
                        if let watts = bat.watts {
                            infoTile(title: "Power Flow", value: String(format: "%.1f W", abs(watts)))
                        }
                        if let v = bat.voltage {
                            infoTile(title: "Voltage", value: String(format: "%.2f V", v))
                        }
                        if let design = bat.designCapacity, let full = bat.fullChargeCapacity {
                            infoTile(title: "Full Charge Capacity", value: "\(full) / \(design) mAh")
                        }
                        if let aw = bat.adapterWatts {
                            infoTile(title: "Connected Charger", value: "\(aw) W")
                        }
                    }

                    // Top Power Apps
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "Top Apps by CPU & Energy Impact")
                        AppTable(store: store, primary: .cpu, limit: 6)
                    }
                } else {
                    Text("No internal battery detected on this Mac.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(20)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
    }

    private func infoTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
