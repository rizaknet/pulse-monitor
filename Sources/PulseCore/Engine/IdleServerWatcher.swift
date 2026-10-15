import Foundation

/// Detects dev servers listening on ports that have been idle for a prolonged period.
final class IdleServerWatcher {
    var busyCPUThreshold = 2.0 // percent
    var idleThreshold: TimeInterval = 30 * 60 // 30 min
    var minUptime: TimeInterval = 15 * 60 // 15 min
    var minMemory: UInt64 = 40 * 1024 * 1024 // 40 MB

    private var lastBusy: [pid_t: Date] = [:]
    private let startedAt = Date()

    func ingest(ports: [ListeningPort], processes: [ProcessUsage], at now: Date = Date()) -> [IdleServer] {
        let procMap = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        var portsByPid: [pid_t: [UInt16]] = [:]
        for lp in ports where !lp.isAppProcess {
            portsByPid[lp.pid, default: []].append(lp.port)
        }

        var idleServers: [IdleServer] = []
        for (pid, pPorts) in portsByPid {
            guard let p = procMap[pid] else { continue }
            let isBusy = p.cpu >= busyCPUThreshold
            if isBusy || lastBusy[pid] == nil {
                lastBusy[pid] = isBusy ? now : max(startedAt, p.startTime)
            }

            let idleTime = now.timeIntervalSince(lastBusy[pid]!)
            let uptime = now.timeIntervalSince(p.startTime)

            if idleTime >= idleThreshold && uptime >= minUptime && p.memory >= minMemory {
                idleServers.append(IdleServer(
                    pid: pid,
                    name: p.name,
                    ports: pPorts.sorted(),
                    memory: p.memory,
                    idleFor: idleTime
                ))
            }
        }

        lastBusy = lastBusy.filter { portsByPid[$0.key] != nil }
        return idleServers.sorted { $0.memory > $1.memory }
    }
}
