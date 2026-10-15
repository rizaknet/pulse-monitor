import Foundation
import Darwin
import IOKit
import SystemConfiguration

/// Machine-wide CPU, memory, network, disk and GPU. Owned and called only by `SamplingEngine`.
final class SystemProbe {
    private var lastTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
    private var lastNet: (UInt64, UInt64)?
    private var lastDisk: (UInt64, UInt64)?
    private var lastAt: UInt64 = 0
    private var session = (down: UInt64(0), up: UInt64(0), read: UInt64(0), written: UInt64(0))
    private var diskSpace: (Int64, Int64) = (0, 0)
    private var diskSpaceAt: UInt64 = 0
    private var interface = "—"
    private var interfaceAt: UInt64 = 0

    func sample() -> SystemStats {
        var s = SystemStats()
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let dt = lastAt > 0 ? Double(now - lastAt) / 1e9 : 0
        lastAt = now

        cpu(into: &s)
        memory(into: &s)

        var la = [Double](repeating: 0, count: 3)
        if getloadavg(&la, 3) > 0 { s.loadAverage = la[0] }

        let net = networkBytes()
        if let l = lastNet, dt > 0 {
            let dIn = net.0 >= l.0 ? net.0 - l.0 : 0, dOut = net.1 >= l.1 ? net.1 - l.1 : 0
            s.netIn = Double(dIn) / dt; s.netOut = Double(dOut) / dt
            session.down &+= dIn; session.up &+= dOut
        }
        lastNet = net

        let disk = diskBytes()
        if let l = lastDisk, dt > 0 {
            let dR = disk.0 >= l.0 ? disk.0 - l.0 : 0, dW = disk.1 >= l.1 ? disk.1 - l.1 : 0
            s.diskRead = Double(dR) / dt; s.diskWrite = Double(dW) / dt
            session.read &+= dR; session.written &+= dW
        }
        lastDisk = disk
        s.sessionDownloaded = session.down; s.sessionUploaded = session.up
        s.sessionRead = session.read; s.sessionWritten = session.written

        if diskSpaceAt == 0 || now - diskSpaceAt > 30_000_000_000 {
            diskSpaceAt = now
            let url = URL(fileURLWithPath: "/")
            if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
                diskSpace = (Int64(v.volumeTotalCapacity ?? 0), v.volumeAvailableCapacityForImportantUsage ?? 0)
            }
        }
        s.diskTotal = diskSpace.0
        s.diskFree = diskSpace.1

        if interfaceAt == 0 || now - interfaceAt > 20_000_000_000 {
            interfaceAt = now
            interface = Self.primaryInterfaceName()
        }
        s.interfaceName = interface
        s.gpu = gpuUtilization()
        return s
    }

    // MARK: CPU

    private func cpu(into s: inout SystemStats) {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return }
        defer { vmDeallocate(info, count: Int(infoCount)) }

        var ticks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
        ticks.reserveCapacity(Int(count))
        for i in 0..<Int(count) {
            let b = Int(CPU_STATE_MAX) * i
            func t(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[b + Int(state)]) }
            ticks.append((t(CPU_STATE_USER), t(CPU_STATE_SYSTEM), t(CPU_STATE_IDLE), t(CPU_STATE_NICE)))
        }
        defer { lastTicks = ticks }
        guard lastTicks.count == ticks.count else { return }

        var sumUser = 0.0, sumSys = 0.0, sumAll = 0.0
        var perCore: [Double] = []
        perCore.reserveCapacity(ticks.count)
        for (n, o) in zip(ticks, lastTicks) {
            // Wrapping subtraction in 32 bits handles counter rollover correctly.
            let du = Double(n.user &- o.user), ds = Double(n.system &- o.system)
            let di = Double(n.idle &- o.idle), dn = Double(n.nice &- o.nice)
            let total = du + ds + di + dn
            perCore.append(total > 0 ? (du + ds + dn) / total : 0)
            sumUser += du + dn; sumSys += ds; sumAll += total
        }
        s.cpuPerCore = perCore
        if sumAll > 0 { s.cpuUser = sumUser / sumAll; s.cpuSystem = sumSys / sumAll }
    }

    // MARK: Memory

    private func memory(into s: inout SystemStats) {
        s.memoryTotal = Hardware.memory
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        if kr == KERN_SUCCESS {
            let page = Hardware.pageSize
            let internalPages = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            s.memoryApp = (internalPages > purgeable ? internalPages - purgeable : 0) * page
            s.memoryWired = UInt64(stats.wire_count) * page
            s.memoryCompressed = UInt64(stats.compressor_page_count) * page
            s.memoryCached = (UInt64(stats.external_page_count) + purgeable) * page
        }
        // The kernel's real pressure state (what Activity Monitor's pressure graph colours by).
        if let level = Sysctl.int32("kern.memorystatus_vm_pressure_level") {
            s.pressure = MemoryPressure(rawValue: Int(level)) ?? (level >= 4 ? .critical : .normal)
        }
        var xsw = xsw_usage()
        var xlen = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &xsw, &xlen, nil, 0) == 0 { s.swapUsed = xsw.xsu_used }
    }

    // MARK: Network (physical en* interfaces only, so VPN tunnels and bridges aren't double counted)

    private func networkBytes() -> (UInt64, UInt64) {
        let rtmIfInfo2: UInt8 = 0x12
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return lastNet ?? (0, 0) }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return lastNet ?? (0, 0) }
        var inBytes: UInt64 = 0, outBytes: UInt64 = 0
        var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
        buf.withUnsafeBytes { p in
            var off = 0
            while off + MemoryLayout<if_msghdr>.size <= len {
                let hdr = p.loadUnaligned(fromByteOffset: off, as: if_msghdr.self)
                if hdr.ifm_msglen == 0 { break }
                if hdr.ifm_type == rtmIfInfo2, off + MemoryLayout<if_msghdr2>.size <= len {
                    let h2 = p.loadUnaligned(fromByteOffset: off, as: if_msghdr2.self)
                    if if_indextoname(UInt32(h2.ifm_index), &nameBuf) != nil,
                       nameBuf[0] == CChar(UInt8(ascii: "e")), nameBuf[1] == CChar(UInt8(ascii: "n")) {
                        inBytes &+= h2.ifm_data.ifi_ibytes
                        outBytes &+= h2.ifm_data.ifi_obytes
                    }
                }
                off += Int(hdr.ifm_msglen)
            }
        }
        return (inBytes, outBytes)
    }

    /// "Wi-Fi", "Ethernet", "Thunderbolt Bridge"… for the interface carrying the default route.
    static func primaryInterfaceName() -> String {
        guard let store = SCDynamicStoreCreate(nil, "Pulse" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let bsd = global["PrimaryInterface"] as? String else { return "Offline" }
        if let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for i in all where (SCNetworkInterfaceGetBSDName(i) as String?) == bsd {
                if let type = SCNetworkInterfaceGetInterfaceType(i), CFEqual(type, kSCNetworkInterfaceTypeIEEE80211) { return "Wi-Fi" }
                if let name = SCNetworkInterfaceGetLocalizedDisplayName(i) as String? { return name }
            }
        }
        return bsd.hasPrefix("utun") ? "VPN" : bsd
    }

    // MARK: Disk IO + GPU (IOKit registry)

    private func diskBytes() -> (UInt64, UInt64) {
        var r: UInt64 = 0, w: UInt64 = 0
        IOKitUtil.forEachService("IOBlockStorageDriver") { e in
            guard let stats = IOKitUtil.dictionary(e, "Statistics") else { return }
            r &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            w &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (r, w)
    }

    private func gpuUtilization() -> Double? {
        var best: Double?
        IOKitUtil.forEachService("IOAccelerator") { e in
            guard let perf = IOKitUtil.dictionary(e, "PerformanceStatistics"),
                  let u = (perf["Device Utilization %"] as? NSNumber)?.doubleValue else { return }
            best = max(best ?? 0, min(u, 100) / 100)
        }
        return best
    }
}

/// Frees a MIG-returned array. `mach_task_self_` is a C global var, which Swift 6 flags as
/// shared mutable state; it is in fact written once by libsystem before main, so reading it is safe.
private func vmDeallocate(_ p: processor_info_array_t, count: Int) {
    let task = unsafe_mach_task_self()
    vm_deallocate(task, vm_address_t(UInt(bitPattern: p)), vm_size_t(count * MemoryLayout<integer_t>.stride))
}

@inline(__always) private func unsafe_mach_task_self() -> mach_port_t {
    // `mach_task_self()` is a macro in C; read the backing symbol through a nonisolated(unsafe) alias.
    nonisolated(unsafe) let t = mach_task_self_
    return t
}

enum IOKitUtil {
    static func forEachService(_ cls: String, _ body: (io_object_t) -> Void) {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }
        var e = IOIteratorNext(iter)
        while e != 0 {
            body(e)
            IOObjectRelease(e)
            e = IOIteratorNext(iter)
        }
    }

    static func property(_ e: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(e, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func dictionary(_ e: io_object_t, _ key: String) -> [String: Any]? { property(e, key) as? [String: Any] }
}
