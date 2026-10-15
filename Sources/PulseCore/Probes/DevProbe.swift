import Foundation

/// Detection of dev projects from working directory markers.
public enum ProjectLocator {
    private static let markers = [
        ".git", "package.json", "Cargo.toml", "go.mod",
        "pyproject.toml", "Package.swift", "Gemfile",
        "docker-compose.yml", "compose.yaml"
    ]

    /// Walk up from dir to nearest folder with marker, within user's home directory.
    public static func findRoot(for dir: String) -> String? {
        let home = NSHomeDirectory()
        guard dir.hasPrefix(home) && dir != home else { return nil }

        var cur = dir
        var result: String?
        while cur.hasPrefix(home) && cur != home {
            let fm = FileManager.default
            if markers.contains(where: { fm.fileExists(atPath: (cur as NSString).appendingPathComponent($0)) }) {
                result = cur
                if fm.fileExists(atPath: (cur as NSString).appendingPathComponent(".git")) {
                    break
                }
            }
            cur = (cur as NSString).deletingLastPathComponent
        }
        return result
    }
}

/// Slow lane developer environment probe (projects and ports).
final class DevProbe {
    private var rootCache: [String: String?] = [:]

    func sample(processes: [ProcessUsage]) -> (projects: [DevProject], ports: [ListeningPort]) {
        let myUID = getuid()
        var ports: [ListeningPort] = []
        var projectMap: [String: (name: String, pids: Set<pid_t>, ports: Set<UInt16>, mem: UInt64, cpu: Double)] = [:]

        for p in processes where p.uid == myUID {
            let pPorts = ProcessProbe.listeningPorts(pid: p.pid)
            let isApp = AppGrouper.outermostApp(p.path) != nil

            for port in pPorts {
                ports.append(ListeningPort(
                    port: port,
                    pid: p.pid,
                    processName: p.name,
                    memory: p.memory,
                    startTime: p.startTime,
                    isAppProcess: isApp
                ))
            }

            // Only associate non-app (terminal/CLI/dev-server) processes with project directories
            if !isApp {
                if let cwd = ProcessProbe.workingDirectory(pid: p.pid) {
                    let root: String?
                    if let cached = rootCache[cwd] {
                        root = cached
                    } else {
                        root = ProjectLocator.findRoot(for: cwd)
                        rootCache[cwd] = root
                    }

                    if let root = root {
                        let name = (root as NSString).lastPathComponent
                        var entry = projectMap[root, default: (name: name, pids: [], ports: [], mem: 0, cpu: 0)]
                        entry.pids.insert(p.pid)
                        entry.ports.formUnion(pPorts)
                        entry.mem &+= p.memory
                        entry.cpu += p.cpu
                        projectMap[root] = entry
                    }
                }
            }
        }

        // Limit cache size to avoid unbounded memory
        if rootCache.count > 500 { rootCache.removeAll(keepingCapacity: true) }

        let projects = projectMap.map { (root, data) in
            DevProject(
                id: root,
                name: data.name,
                pids: Array(data.pids).sorted(),
                ports: Array(data.ports).sorted(),
                memory: data.mem,
                cpu: data.cpu
            )
        }.sorted { $0.memory > $1.memory }

        return (projects, ports.sorted { $0.port < $1.port })
    }
}
