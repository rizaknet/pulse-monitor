import Foundation
import Darwin

/// Per-process CPU, memory and disk via libproc. Owned and called only by `SamplingEngine`.
final class ProcessProbe {
    private struct Identity {
        let startAbs: UInt64             // ri_proc_start_abstime: detects PID reuse
        let name: String
        let path: String
        let start: Date
        let ppid: pid_t
        let uid: uid_t
    }
    private struct Prev { var cpuNs: UInt64; var read: UInt64; var write: UInt64; var at: UInt64 }

    private var prev: [pid_t: Prev] = [:]
    private var identity: [pid_t: Identity] = [:]
    private var pids: [pid_t] = []
    private let numer: UInt64
    private let denom: UInt64

    init() {
        var tb = mach_timebase_info()
        mach_timebase_info(&tb)
        numer = UInt64(tb.numer)
        denom = UInt64(max(tb.denom, 1))
    }

    private func ns(_ ticks: UInt64) -> UInt64 { ticks / denom * numer + (ticks % denom) * numer / denom }

    func sample() -> [ProcessUsage] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        let want = Int(n) + 64
        if pids.count < want { pids = [pid_t](repeating: 0, count: want) }
        let got = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard got > 0 else { return [] }

        let now = ns(mach_absolute_time())
        var out: [ProcessUsage] = []
        out.reserveCapacity(got)
        var seen = Set<pid_t>(minimumCapacity: got)

        for i in 0..<min(got, pids.count) {
            let pid = pids[i]
            guard pid > 0 else { continue }
            seen.insert(pid)

            var ri = rusage_info_v4()
            let rc = withUnsafeMutablePointer(to: &ri) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            let startAbs = rc == 0 ? ri.ri_proc_start_abstime : 0
            if let cached = identity[pid], rc != 0 || cached.startAbs == startAbs {
                // keep cached identity
            } else {
                identity[pid] = makeIdentity(pid, startAbs: startAbs)
                prev[pid] = nil          // new process behind a reused PID: restart deltas
            }
            guard let id = identity[pid] else { continue }

            var s = ProcessUsage(pid: pid, ppid: id.ppid, uid: id.uid, name: id.name, path: id.path, startTime: id.start)
            if rc == 0 {
                s.measured = true
                s.memory = ri.ri_phys_footprint
                let cpuNs = ns(ri.ri_user_time &+ ri.ri_system_time)
                if let p = prev[pid], now > p.at {
                    let wall = Double(now - p.at)
                    s.cpu = cpuNs >= p.cpuNs ? Double(cpuNs - p.cpuNs) / wall * 100 : 0
                    let secs = wall / 1e9
                    s.diskRead = ri.ri_diskio_bytesread >= p.read ? Double(ri.ri_diskio_bytesread - p.read) / secs : 0
                    s.diskWrite = ri.ri_diskio_byteswritten >= p.write ? Double(ri.ri_diskio_byteswritten - p.write) / secs : 0
                }
                prev[pid] = Prev(cpuNs: cpuNs, read: ri.ri_diskio_bytesread, write: ri.ri_diskio_byteswritten, at: now)
            }
            out.append(s)
        }
        if prev.count > seen.count { prev = prev.filter { seen.contains($0.key) } }
        if identity.count > seen.count { identity = identity.filter { seen.contains($0.key) } }
        return out
    }

    private func makeIdentity(_ pid: pid_t, startAbs: UInt64) -> Identity? {
        var path = ""
        var pbuf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if proc_pidpath(pid, &pbuf, UInt32(pbuf.count)) > 0 { path = String(cString: pbuf) }
        // Normalise firmlinked paths so one app never shows up under two keys.
        if path.hasPrefix("/System/Volumes/Data/") { path.removeFirst("/System/Volumes/Data".count) }

        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size {
            var name = cString(info.pbi_name)
            if name.isEmpty { name = cString(info.pbi_comm) }
            if !path.isEmpty { name = (path as NSString).lastPathComponent }
            let start = Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1e6)
            return Identity(startAbs: startAbs, name: name, path: path, start: start, ppid: pid_t(info.pbi_ppid), uid: info.pbi_uid)
        }
        var short = proc_bsdshortinfo()
        let ss = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &short, ss) == ss else { return nil }
        let name = path.isEmpty ? cString(short.pbsi_comm) : (path as NSString).lastPathComponent
        return Identity(startAbs: startAbs, name: name, path: path, start: Hardware.bootTime, ppid: pid_t(short.pbsi_ppid), uid: short.pbsi_uid)
    }

    // MARK: Slow-lane helpers (ports + working directory)

    /// TCP ports this process is listening on.
    static func listeningPorts(pid: pid_t) -> [UInt16] {
        let bufSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufSize > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bufSize) / stride + 8)
        let used = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * stride))
        guard used > 0 else { return [] }
        var ports = Set<UInt16>()
        for fd in fds.prefix(Int(used) / stride) where Int(fd.proc_fdtype) == Int(PROX_FDTYPE_SOCKET) {
            var si = socket_fdinfo()
            let sz = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &si, sz) == sz,
                  Int(si.psi.soi_kind) == Int(SOCKINFO_TCP) else { continue }
            let tcp = si.psi.soi_proto.pri_tcp
            guard Int(tcp.tcpsi_state) == Int(TSI_S_LISTEN) else { continue }
            let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport))
            if port > 0 { ports.insert(port) }
        }
        return ports.sorted()
    }

    static func workingDirectory(pid: pid_t) -> String? {
        var v = proc_vnodepathinfo()
        let sz = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &v, sz) == sz else { return nil }
        let p = cString(v.pvi_cdir.vip_path)
        return p.isEmpty ? nil : p
    }
}

/// Reads a fixed-size C char tuple as a String.
func cString<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { raw in String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self) }
}
