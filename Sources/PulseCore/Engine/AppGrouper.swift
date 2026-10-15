import Foundation

/// Groups individual processes into high-level AppUsage entities.
public enum AppGrouper {
    public static let systemID = "system"

    /// Finds the outermost `.app` in the path so helpers fold into the parent app.
    public static func outermostApp(_ path: String) -> String? {
        guard let r = path.range(of: ".app/") else {
            return path.hasSuffix(".app") ? path : nil
        }
        return String(path[..<r.lowerBound]) + ".app"
    }

    public static func group(_ processes: [ProcessUsage]) -> [AppUsage] {
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        let myUID = getuid()
        var groups: [String: (name: String, kind: AppKind, bundlePath: String?, procs: [ProcessUsage])] = [:]

        for p in processes {
            let key: String
            let name: String
            let kind: AppKind
            let bundle: String?

            if let app = outermostApp(p.path) {
                key = app
                bundle = app
                kind = .app
                name = FileManager.default.displayName(atPath: app).replacingOccurrences(of: ".app", with: "")
            } else if p.uid != myUID || p.path.hasPrefix("/System/") || p.path.hasPrefix("/usr/libexec") || p.path.hasPrefix("/usr/sbin") || p.path.isEmpty {
                key = systemID
                name = "macOS"
                kind = .system
                bundle = nil
            } else {
                // Command line process: walk up ancestry to see if an App (e.g. Terminal, VSCode, iTerm) launched it
                var cur = p.ppid
                var hops = 0
                var foundApp: String?
                while cur > 1, hops < 12, let parent = byPID[cur] {
                    if let app = outermostApp(parent.path) {
                        foundApp = app
                        break
                    }
                    cur = parent.ppid
                    hops += 1
                }

                if let app = foundApp {
                    key = app
                    bundle = app
                    kind = .app
                    name = FileManager.default.displayName(atPath: app).replacingOccurrences(of: ".app", with: "")
                } else {
                    key = "exec:" + p.path
                    name = p.name
                    kind = .commandLine
                    bundle = nil
                }
            }

            if var existing = groups[key] {
                existing.procs.append(p)
                groups[key] = existing
            } else {
                groups[key] = (name: name, kind: kind, bundlePath: bundle, procs: [p])
            }
        }

        return groups.map { (key, val) in
            AppUsage(id: key, name: val.name, kind: val.kind, bundlePath: val.bundlePath, processes: val.procs)
        }
    }
}
