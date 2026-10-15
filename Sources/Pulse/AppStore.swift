import Foundation
import SwiftUI
import Observation
import UserNotifications
import PulseCore

@MainActor
@Observable
final class AppStore {
    var snapshot = Snapshot()
    var dev = DevState()                 // last slow-lane result (kept between ticks)
    var activeTab: PulseTab = .overview
    var selectedAppID: String? = nil
    var isWindowOpen = false
    var isPanelOpen = false
    var hasData = false

    var cpuHistory = MetricHistory()
    var memHistory = MetricHistory()
    var netInHistory = MetricHistory()
    var netOutHistory = MetricHistory()
    var diskHistory = MetricHistory()
    var gpuHistory = MetricHistory()
    var batteryHistory = MetricHistory(fineCapacity: 150, coarseCapacity: 240, bucket: 60)

    var alerts: [PulseAlert] = []
    let settings = PulseSettings()

    private let engine = SamplingEngine()
    private var loop: Task<Void, Never>?
    private var sleeper: Task<Void, Never>?

    init() {
        if let i = CommandLine.arguments.firstIndex(of: "--tab"), i + 1 < CommandLine.arguments.count,
           let t = PulseTab(rawValue: CommandLine.arguments[i + 1]) {
            activeTab = t
        }
        startSamplingLoop()
        requestNotificationPermission()
    }

    var currentInterval: TimeInterval {
        (isWindowOpen || isPanelOpen) ? settings.activeSamplingInterval : settings.idleSamplingInterval
    }

    /// Wakes the loop early (e.g. when the window opens) so fresh data appears at once.
    func wake() { sleeper?.cancel() }

    private func startSamplingLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.currentInterval
                let snap = await self.engine.sample(interval: interval)
                self.apply(snap)
                let nap: Task<Void, Never> = Task {
                    _ = try? await Task.sleep(for: .seconds(interval))
                }
                self.sleeper = nap
                await nap.value
            }
        }
    }

    private func apply(_ s: Snapshot) {
        snapshot = s
        hasData = true
        if let d = s.dev { dev = d }
        let now = s.date

        cpuHistory.append(s.system.cpuTotal, at: now)
        memHistory.append(s.system.memoryFraction, at: now)
        netInHistory.append(s.system.netIn, at: now)
        netOutHistory.append(s.system.netOut, at: now)
        diskHistory.append(s.system.diskRead + s.system.diskWrite, at: now)
        gpuHistory.append(s.system.gpu ?? 0, at: now)
        if let b = s.battery { batteryHistory.append(Double(b.level) / 100, at: now) }

        guard !s.newAlerts.isEmpty else { return }
        for alert in s.newAlerts {
            if let idx = alerts.firstIndex(where: { $0.key == alert.key }) {
                var existing = alerts.remove(at: idx)
                existing.count += 1
                existing.date = alert.date
                existing.detail = alert.detail
                alerts.insert(existing, at: 0)
            } else {
                alerts.insert(alert, at: 0)
            }
            if settings.sendNotifications { sendNotification(alert) }
        }
        if alerts.count > 50 { alerts = Array(alerts.prefix(50)) }
    }

    // MARK: Lookups

    func app(_ id: String?) -> AppUsage? {
        guard let id else { return nil }
        return snapshot.apps.first { $0.id == id }
    }

    func busiest(by metric: (AppUsage) -> Double) -> AppUsage? {
        snapshot.apps.max { metric($0) < metric($1) }
    }

    // MARK: Actions

    func terminate(app: AppUsage, force: Bool) {
        ProcessActions.terminateGroup(pids: app.processes.map(\.pid), bundlePath: app.bundlePath, force: force)
        if selectedAppID == app.id { selectedAppID = nil }
        refreshSoon()
    }

    func terminate(pid: pid_t, force: Bool) {
        _ = ProcessActions.terminate(pid: pid, force: force)
        refreshSoon()
    }

    private func refreshSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            wake()
        }
    }

    // MARK: Notifications

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(_ alert: PulseAlert) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.detail
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: alert.key, content: content, trigger: nil))
    }
}
