import Foundation

/// Actor-isolated background sampling engine.
/// Builds immutable `Snapshot` structs and delivers them asynchronously.
public actor SamplingEngine {
    private let sysProbe = SystemProbe()
    private let procProbe = ProcessProbe()
    private let gpuProbe = GPUProbe()
    private let netProbe = AppNetProbe()
    private let devProbe = DevProbe()
    private let idleWatcher = IdleServerWatcher()
    private let alertEngine = AlertEngine()

    private var appNetRates: [pid_t: (Double, Double)] = [:]
    private var netReady = false
    private var tickCount = 0

    public init() {
        // Pre-warm baseline
        _ = sysProbe.sample()
        _ = procProbe.sample()
    }

    public func sample(interval: TimeInterval) async -> Snapshot {
        tickCount += 1
        var snapshot = Snapshot()
        let now = Date()
        snapshot.date = now

        // Check if we need nettop refresh (~every 30s)
        if tickCount % 15 == 1 {
            netProbe.refresh { [weak self] rates in
                guard let self = self else { return }
                Task {
                    await self.updateNetRates(rates)
                }
            }
        }

        // Fast lane sampling (CPU, Mem, Disk, GPU, Procs)
        let systemStats = sysProbe.sample()
        var procs = procProbe.sample()
        let gpuMap = gpuProbe.sample()

        let net = self.appNetRates
        for i in procs.indices {
            let pid = procs[i].pid
            procs[i].gpu = gpuMap[pid] ?? 0.0
            if let n = net[pid] {
                procs[i].netIn = n.0
                procs[i].netOut = n.1
            }
        }

        let apps = AppGrouper.group(procs)
            .sorted { ($0.cpu + Double($0.memory) / 1e10) > ($1.cpu + Double($1.memory) / 1e10) }

        snapshot.system = systemStats
        snapshot.apps = apps
        snapshot.processCount = procs.count
        snapshot.unmeasuredCount = procs.filter { !$0.measured }.count
        snapshot.battery = BatteryProbe.sample()
        snapshot.appNetworkReady = netReady

        // Slow lane sampling (every ~10s: ports, projects, idle servers, sleep blockers)
        var idleServers: [IdleServer] = []
        if tickCount % 5 == 1 {
            let (projects, ports) = devProbe.sample(processes: procs)
            idleServers = idleWatcher.ingest(ports: ports, processes: procs, at: now)
            let blockers = PowerAssertions.current()
            let (agents, quotas) = AgentsProbe.sample(processes: procs, ports: ports)

            var dev = DevState()
            dev.projects = projects
            dev.ports = ports
            dev.idleServers = idleServers
            dev.blockers = blockers
            dev.agents = agents
            dev.quotas = quotas
            snapshot.dev = dev
        }

        // Alert detection
        snapshot.newAlerts = alertEngine.ingest(
            apps: apps,
            system: systemStats,
            idleServers: idleServers,
            interval: interval,
            at: now
        )

        return snapshot
    }

    private func updateNetRates(_ rates: [pid_t: (Double, Double)]) {
        self.appNetRates = rates
        self.netReady = true
    }
}
