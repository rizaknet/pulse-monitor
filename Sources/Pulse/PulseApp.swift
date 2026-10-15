import SwiftUI
import AppKit
import PulseCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openPulseMainWindow, object: nil)
        return true
    }
}

extension Notification.Name {
    static let openPulseMainWindow = Notification.Name("openPulseMainWindow")
}

@main
struct PulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store = AppStore()

    init() {
        if CommandLine.arguments.contains("--test") {
            PulseCoreSelfTest.run()
            exit(0)
        }

        if CommandLine.arguments.contains("--dump") {
            runCliDump()
        }
    }

    var body: some Scene {
        Window("Pulse", id: "main") {
            MainWindowView(store: store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 700)

        MenuBarExtra {
            MenuBarPanelView(store: store)
        } label: {
            MenuBarLabelView(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: store.settings)
        }
    }

    private func runCliDump() {
        Task {
            let engine = SamplingEngine()
            let snap = await engine.sample(interval: 2.0)
            let sys = snap.system
            print("=== Pulse Diagnostic Dump ===")
            print("Hardware: \(Hardware.summary)")
            print("CPU: \(Format.percent(sys.cpuTotal)) (User: \(Format.percent(sys.cpuUser)), Sys: \(Format.percent(sys.cpuSystem))) Cores: \(Hardware.cores) Load: \(String(format: "%.2f", sys.loadAverage))")
            print("Memory: Used \(Format.bytes(sys.memoryUsed)) / \(Format.bytes(sys.memoryTotal)) App: \(Format.bytes(sys.memoryApp)) Wired: \(Format.bytes(sys.memoryWired)) Pressure: \(sys.pressure.label)")
            print("Network: In \(Format.rate(sys.netIn)) Out \(Format.rate(sys.netOut)) [\(sys.interfaceName)]")
            print("Disk: Read \(Format.rate(sys.diskRead)) Write \(Format.rate(sys.diskWrite)) Free: \(Format.bytes(sys.diskFree))")
            if let g = sys.gpu { print("GPU: \(Format.percent(g))") }
            if let b = snap.battery { print("Battery: \(b.level)% (Charging: \(b.isCharging), Watts: \(String(format: "%.1f", b.watts ?? 0)))") }
            print("Apps Monitored: \(snap.apps.count) (Total Processes: \(snap.processCount), Unmeasured: \(snap.unmeasuredCount))")
            print("Top 5 Apps:")
            for app in snap.apps.prefix(5) {
                print("  - \(app.name): CPU \(Format.cpuShare(app.cpu)), Mem \(Format.bytes(app.memory)), Procs: \(app.processes.count)")
            }
            exit(0)
        }
    }
}

struct SettingsView: View {
    @Bindable var settings: PulseSettings
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Menu Bar") {
                Picker("Display Format", selection: $settings.menuBarMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            }

            Section("Sampling Cadence") {
                Picker("Active Window Interval", selection: $settings.activeSamplingInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds (Recommended)").tag(2.0)
                    Text("3 seconds").tag(3.0)
                }

                Picker("Background Interval", selection: $settings.idleSamplingInterval) {
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds (Lightweight)").tag(5.0)
                    Text("10 seconds").tag(10.0)
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, val in
                        LoginItem.setEnabled(val)
                    }

                Toggle("Send Resource Strain Notifications", isOn: $settings.sendNotifications)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 280)
        .padding()
    }
}
