import Foundation
import Darwin

public enum Sysctl {
    public static func string(_ name: String) -> String? {
        var len = 0
        guard sysctlbyname(name, nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: len)
        guard sysctlbyname(name, &buf, &len, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    public static func int32(_ name: String) -> Int32? {
        var v: Int32 = 0
        var len = MemoryLayout<Int32>.size
        return sysctlbyname(name, &v, &len, nil, 0) == 0 ? v : nil
    }
}

public enum Hardware {
    public static let chip = Sysctl.string("machdep.cpu.brand_string") ?? "Mac"
    public static let model = Sysctl.string("hw.model") ?? "Mac"
    public static let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
    public static let performanceCores = Int(Sysctl.int32("hw.perflevel0.logicalcpu") ?? 0)
    public static let efficiencyCores = Int(Sysctl.int32("hw.perflevel1.logicalcpu") ?? 0)
    public static let memory = ProcessInfo.processInfo.physicalMemory
    public static let pageSize = UInt64(max(4096, sysconf(_SC_PAGESIZE)))

    public static let bootTime: Date = {
        var tv = timeval()
        var len = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &len, nil, 0) == 0 else { return Date() }
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec))
    }()

    public static var uptime: TimeInterval { Date().timeIntervalSince(bootTime) }

    public static var summary: String {
        var parts = [chip, "\(cores) cores", Format.bytes(memory, compact: true)]
        if performanceCores > 0, efficiencyCores > 0 { parts[1] = "\(performanceCores)P + \(efficiencyCores)E cores" }
        return parts.joined(separator: " · ")
    }
}
