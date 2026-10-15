import Foundation

// All values that cross from the sampling actor to the UI are immutable, Sendable value types.

public enum MemoryPressure: Int, Sendable, Comparable {
    case normal = 1, warning = 2, critical = 4
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    public var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Elevated"
        case .critical: "Critical"
        }
    }
}

public struct SystemStats: Sendable {
    public var cpuUser = 0.0             // 0…1 of the whole machine
    public var cpuSystem = 0.0
    public var cpuPerCore: [Double] = []
    public var loadAverage = 0.0

    public var memoryTotal: UInt64 = 0
    public var memoryApp: UInt64 = 0
    public var memoryWired: UInt64 = 0
    public var memoryCompressed: UInt64 = 0
    public var memoryCached: UInt64 = 0
    public var swapUsed: UInt64 = 0
    public var pressure: MemoryPressure = .normal

    public var netIn = 0.0               // bytes/s, physical interfaces only
    public var netOut = 0.0
    public var interfaceName = "—"       // "Wi-Fi", "Ethernet", …

    public var diskRead = 0.0            // bytes/s
    public var diskWrite = 0.0
    public var diskTotal: Int64 = 0
    public var diskFree: Int64 = 0

    public var gpu: Double?              // 0…1

    // Byte counters accumulated from raw deltas since Pulse started.
    public var sessionDownloaded: UInt64 = 0
    public var sessionUploaded: UInt64 = 0
    public var sessionRead: UInt64 = 0
    public var sessionWritten: UInt64 = 0

    public init() {}

    public var cpuTotal: Double { min(1, cpuUser + cpuSystem) }
    public var memoryUsed: UInt64 { memoryApp + memoryWired + memoryCompressed }
    public var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
    public var diskUsedFraction: Double { diskTotal > 0 ? Double(diskTotal - diskFree) / Double(diskTotal) : 0 }
}

public struct ProcessUsage: Sendable, Identifiable, Hashable {
    public let pid: pid_t
    public let ppid: pid_t
    public let uid: uid_t
    public let name: String
    public let path: String
    public let startTime: Date
    public var memory: UInt64 = 0
    public var cpu = 0.0                 // percent of ONE core (Activity Monitor style, may exceed 100)
    public var diskRead = 0.0            // bytes/s
    public var diskWrite = 0.0
    public var gpu = 0.0                 // 0…1 of GPU time
    public var netIn = 0.0               // bytes/s (refreshed every ~30 s)
    public var netOut = 0.0
    public var measured = false          // false for processes we may not inspect (other users / root)
    public var id: pid_t { pid }

    public init(pid: pid_t, ppid: pid_t, uid: uid_t, name: String, path: String, startTime: Date) {
        self.pid = pid; self.ppid = ppid; self.uid = uid; self.name = name; self.path = path; self.startTime = startTime
    }
}

public enum AppKind: String, Sendable { case app, commandLine, system }

/// Processes folded into the app that owns them. Totals are computed once when the group is built.
public struct AppUsage: Sendable, Identifiable {
    public let id: String                // bundle identifier, or bundle path / exec path
    public let name: String
    public let kind: AppKind
    public let bundlePath: String?
    public let processes: [ProcessUsage]
    public let cpu: Double               // percent of one core, summed
    public let memory: UInt64
    public let gpu: Double
    public let diskRead: Double
    public let diskWrite: Double
    public let netIn: Double
    public let netOut: Double

    public init(id: String, name: String, kind: AppKind, bundlePath: String?, processes: [ProcessUsage]) {
        self.id = id; self.name = name; self.kind = kind; self.bundlePath = bundlePath; self.processes = processes
        var cpu = 0.0, mem: UInt64 = 0, gpu = 0.0, dr = 0.0, dw = 0.0, ni = 0.0, no = 0.0
        for p in processes {
            cpu += p.cpu; mem &+= p.memory; gpu += p.gpu
            dr += p.diskRead; dw += p.diskWrite; ni += p.netIn; no += p.netOut
        }
        self.cpu = cpu; self.memory = mem; self.gpu = min(gpu, 1)
        self.diskRead = dr; self.diskWrite = dw; self.netIn = ni; self.netOut = no
    }

    public var diskIO: Double { diskRead + diskWrite }
    public var network: Double { netIn + netOut }
}

public struct BatteryInfo: Sendable, Equatable {
    public var level = 0                 // percent
    public var isCharging = false
    public var isPluggedIn = false
    public var minutesToEmpty: Int?
    public var minutesToFull: Int?
    public var cycleCount: Int?
    public var health: Double?           // full-charge capacity / design capacity
    public var designCapacity: Int?      // mAh
    public var fullChargeCapacity: Int?  // mAh
    public var watts: Double?            // positive = drawing from battery, negative = charging
    public var voltage: Double?          // volts
    public var adapterWatts: Int?
    public var temperature: Int?         // degrees Celsius
    public init() {}
}

public struct ListeningPort: Sendable, Identifiable, Hashable {
    public let port: UInt16
    public let pid: pid_t
    public let processName: String
    public let memory: UInt64
    public let startTime: Date
    public let isAppProcess: Bool
    public var id: String { "\(pid):\(port)" }
    public var isDynamic: Bool { port >= 49152 }
}

public struct DevProject: Sendable, Identifiable {
    public let id: String                // project root path
    public let name: String
    public let pids: [pid_t]
    public let ports: [UInt16]
    public let memory: UInt64
    public let cpu: Double
}

public struct IdleServer: Sendable, Identifiable {
    public let pid: pid_t
    public let name: String
    public let ports: [UInt16]
    public let memory: UInt64
    public let idleFor: TimeInterval
    public var id: pid_t { pid }
}

public struct SleepBlocker: Sendable, Identifiable {
    public enum Kind: String, Sendable { case display, system }
    public let pid: pid_t
    public let processName: String
    public let kind: Kind
    public let reason: String
    public var id: String { "\(pid)-\(kind.rawValue)-\(reason)" }
}

public struct AgentWorker: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: String          // e.g. "command", "server", "browser", "tool server"
    public let cpu: Double
    public let memory: UInt64
    public let pid: pid_t

    public init(id: String, name: String, kind: String, cpu: Double, memory: UInt64, pid: pid_t) {
        self.id = id; self.name = name; self.kind = kind; self.cpu = cpu; self.memory = memory; self.pid = pid
    }
}

public struct AgentSession: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let agentName: String     // "Claude Code", "Codex", "Cursor Agent", "Antigravity"
    public let project: String
    public let isWorking: Bool
    public let runtime: TimeInterval
    public let memory: UInt64
    public let pids: [pid_t]
    public let workers: [AgentWorker]

    public init(id: String, title: String, agentName: String, project: String, isWorking: Bool, runtime: TimeInterval, memory: UInt64, pids: [pid_t], workers: [AgentWorker]) {
        self.id = id; self.title = title; self.agentName = agentName; self.project = project; self.isWorking = isWorking
        self.runtime = runtime; self.memory = memory; self.pids = pids; self.workers = workers
    }
}

/// Slow-lane data (ports, projects, …), refreshed every ~10 s.
public struct DevState: Sendable {
    public var projects: [DevProject] = []
    public var ports: [ListeningPort] = []
    public var idleServers: [IdleServer] = []
    public var blockers: [SleepBlocker] = []
    public var agents: [AgentSession] = []
    public init() {}
}

public struct PulseAlert: Sendable, Identifiable {
    public enum Kind: String, Sendable { case sustainedCPU, memoryGrowth, memoryPressure, idleServer, networkBurst, diskBurst }
    public let id = UUID()
    public let kind: Kind
    public let key: String               // de-duplication key
    public let appID: String?
    public let bundlePath: String?
    public let title: String
    public var detail: String
    public var date: Date
    public var count = 1

    public init(kind: Kind, key: String, appID: String?, bundlePath: String?, title: String, detail: String, date: Date) {
        self.kind = kind; self.key = key; self.appID = appID; self.bundlePath = bundlePath
        self.title = title; self.detail = detail; self.date = date
    }
}

public struct Snapshot: Sendable {
    public var date = Date()
    public var system = SystemStats()
    public var apps: [AppUsage] = []
    public var processCount = 0
    public var unmeasuredCount = 0
    public var battery: BatteryInfo?
    public var dev: DevState?            // nil when the slow lane did not run this tick
    public var newAlerts: [PulseAlert] = []
    public var appNetworkReady = false
    public init() {}
}
