import Foundation

/// Per-app network counters via periodic nettop invocation on a background queue.
final class AppNetProbe: @unchecked Sendable {
    private var prev: [pid_t: (UInt64, UInt64)] = [:]
    private var prevAt: Date?
    private let queue = DispatchQueue(label: "com.rizak.pulse.nettop", qos: .utility)
    private var running = false

    func refresh(_ completion: @escaping @Sendable ([pid_t: (Double, Double)]) -> Void) {
        queue.async { [self] in
            guard !running else { return }
            running = true
            defer { running = false }

            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
            p.arguments = ["-P", "-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice

            var cur: [pid_t: (UInt64, UInt64)] = [:]
            if (try? p.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let output = String(decoding: data, as: UTF8.self)
                for line in output.split(separator: "\n").dropFirst() {
                    let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                    guard fields.count >= 3,
                          let dotIndex = fields[0].lastIndex(of: "."),
                          let pid = Int32(fields[0][fields[0].index(after: dotIndex)...]),
                          let bin = UInt64(fields[1]),
                          let bout = UInt64(fields[2]) else { continue }
                    cur[pid] = (bin, bout)
                }
            }

            let now = Date()
            var rates: [pid_t: (Double, Double)] = [:]
            if let at = prevAt {
                let dt = now.timeIntervalSince(at)
                if dt > 0 {
                    for (pid, v) in cur {
                        guard let p = prev[pid] else { continue }
                        let inRate = v.0 >= p.0 ? Double(v.0 - p.0) / dt : 0
                        let outRate = v.1 >= p.1 ? Double(v.1 - p.1) / dt : 0
                        rates[pid] = (inRate, outRate)
                    }
                }
            }
            prev = cur
            prevAt = now
            completion(rates)
        }
    }
}
