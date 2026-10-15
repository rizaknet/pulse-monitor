import Foundation

/// Analyzes resource trends to fire actionable alerts (CPU hogs, memory leaks, etc.).
final class AlertEngine {
    var cpuThreshold = 75.0 // percent
    var cpuWindow: TimeInterval = 10 * 60
    var memoryGrowthBytes: UInt64 = 1024 * 1024 * 1024 // 1 GB
    var memoryWindow: TimeInterval = 60 * 60
    var networkBurstBytes: Double = 1024 * 1024 * 1024 // 1 GB in 10 min
    var diskBurstBytes: Double = 5 * 1024 * 1024 * 1024 // 5 GB in 10 min
    var burstWindow: TimeInterval = 10 * 60
    var cooldown: TimeInterval = 45 * 60

    private struct HistoryPoint {
        let date: Date
        let cpu: Double
        let mem: UInt64
        let netBytes: Double
        let diskBytes: Double
    }

    private var appHistory: [String: [HistoryPoint]] = [:]
    private var lastFired: [String: Date] = [:]
    private var lastPressureHigh = false

    func ingest(apps: [AppUsage], system: SystemStats, idleServers: [IdleServer], interval: TimeInterval, at now: Date = Date()) -> [PulseAlert] {
        var alerts: [PulseAlert] = []

        for app in apps where app.kind != .system {
            var h = appHistory[app.id, default: []]
            h.append(HistoryPoint(
                date: now,
                cpu: app.cpu,
                mem: app.memory,
                netBytes: app.network * interval,
                diskBytes: app.diskIO * interval
            ))

            let maxKeep = max(cpuWindow, max(memoryWindow, burstWindow))
            h.removeAll { now.timeIntervalSince($0.date) > maxKeep }
            appHistory[app.id] = h

            // 1. Sustained CPU
            let cpuPoints = h.filter { now.timeIntervalSince($0.date) <= cpuWindow }
            if let first = cpuPoints.first, now.timeIntervalSince(first.date) >= cpuWindow * 0.85 {
                let avg = cpuPoints.map(\.cpu).reduce(0, +) / Double(cpuPoints.count)
                if avg >= cpuThreshold {
                    trigger(
                        key: "cpu:\(app.id)",
                        kind: .sustainedCPU,
                        app: app,
                        title: "\(app.name) is keeping the CPU busy",
                        detail: "\(Int(avg))% average over the last \(Int(cpuWindow / 60)) min.",
                        at: now,
                        into: &alerts
                    )
                }
            }

            // 2. Memory Growth
            if let oldest = h.first, now.timeIntervalSince(oldest.date) >= memoryWindow * 0.3,
               app.memory > oldest.mem, (app.memory - oldest.mem) >= memoryGrowthBytes {
                let mins = Int(now.timeIntervalSince(oldest.date) / 60)
                let diff = app.memory - oldest.mem
                trigger(
                    key: "mem:\(app.id)",
                    kind: .memoryGrowth,
                    app: app,
                    title: "\(app.name) memory usage is growing",
                    detail: "Increased by \(Format.bytes(diff)) in the last \(mins) min.",
                    at: now,
                    into: &alerts
                )
            }

            // 3. Network burst
            let burstPoints = h.filter { now.timeIntervalSince($0.date) <= burstWindow }
            let netTotal = burstPoints.map(\.netBytes).reduce(0, +)
            if netTotal >= networkBurstBytes {
                trigger(
                    key: "net:\(app.id)",
                    kind: .networkBurst,
                    app: app,
                    title: "\(app.name) moved heavy network data",
                    detail: "\(Format.bytes(Int64(netTotal))) transferred in \(Int(burstWindow / 60)) min.",
                    at: now,
                    into: &alerts
                )
            }

            // 4. Disk burst
            let diskTotal = burstPoints.map(\.diskBytes).reduce(0, +)
            if diskTotal >= diskBurstBytes {
                trigger(
                    key: "disk:\(app.id)",
                    kind: .diskBurst,
                    app: app,
                    title: "\(app.name) is working the disk heavily",
                    detail: "\(Format.bytes(Int64(diskTotal))) read/written in \(Int(burstWindow / 60)) min.",
                    at: now,
                    into: &alerts
                )
            }
        }

        // Memory pressure alert
        let isHighPressure = system.pressure == .warning || system.pressure == .critical
        if isHighPressure && !lastPressureHigh {
            triggerRaw(
                key: "sys:pressure",
                kind: .memoryPressure,
                appID: nil,
                bundlePath: nil,
                title: "Memory pressure is elevated",
                detail: "macOS is compressing and swapping memory to keep the system responsive.",
                at: now,
                into: &alerts
            )
        }
        lastPressureHigh = isHighPressure

        // Idle servers alert
        if idleServers.count >= 3 {
            let names = idleServers.prefix(3).map(\.name).joined(separator: ", ")
            triggerRaw(
                key: "dev:idleservers",
                kind: .idleServer,
                appID: nil,
                bundlePath: nil,
                title: "\(idleServers.count) dev servers are running but idle",
                detail: "Holding open ports: \(names). Stop them to free resources.",
                at: now,
                into: &alerts
            )
        }

        return alerts
    }

    private func trigger(key: String, kind: PulseAlert.Kind, app: AppUsage, title: String, detail: String, at now: Date, into alerts: inout [PulseAlert]) {
        triggerRaw(key: key, kind: kind, appID: app.id, bundlePath: app.bundlePath, title: title, detail: detail, at: now, into: &alerts)
    }

    private func triggerRaw(key: String, kind: PulseAlert.Kind, appID: String?, bundlePath: String?, title: String, detail: String, at now: Date, into alerts: inout [PulseAlert]) {
        if let last = lastFired[key], now.timeIntervalSince(last) < cooldown { return }
        lastFired[key] = now
        alerts.append(PulseAlert(
            kind: kind,
            key: key,
            appID: appID,
            bundlePath: bundlePath,
            title: title,
            detail: detail,
            date: now
        ))
    }
}
