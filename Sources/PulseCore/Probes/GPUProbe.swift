import Foundation
import IOKit

/// Per-app GPU utilization: AGXDeviceUserClient children of IOAccelerator expose
/// IOUserClientCreator ("pid N, name") and AppUsage[].accumulatedGPUTime (ns).
final class GPUProbe {
    private var prev: [pid_t: UInt64] = [:]
    private var prevAt: UInt64 = 0

    func sample() -> [pid_t: Double] {
        var totals: [pid_t: UInt64] = [:]
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iter) }

        var acc = IOIteratorNext(iter)
        while acc != 0 {
            var children: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(acc, kIOServicePlane, &children) == KERN_SUCCESS {
                var c = IOIteratorNext(children)
                while c != 0 {
                    if let creator = IORegistryEntryCreateCFProperty(c, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                       let usage = IORegistryEntryCreateCFProperty(c, "AppUsage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]] {
                        let head = creator.split(separator: ",").first ?? ""
                        let parts = head.split(separator: " ")
                        if parts.count == 2, let pid = Int32(parts[1]) {
                            let t = usage.reduce(UInt64(0)) { $0 &+ ((($1["accumulatedGPUTime"] as? NSNumber)?.uint64Value) ?? 0) }
                            totals[pid, default: 0] &+= t
                        }
                    }
                    IOObjectRelease(c)
                    c = IOIteratorNext(children)
                }
                IOObjectRelease(children)
            }
            IOObjectRelease(acc)
            acc = IOIteratorNext(iter)
        }

        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        var out: [pid_t: Double] = [:]
        if prevAt > 0, now > prevAt {
            let wall = Double(now - prevAt)
            for (pid, t) in totals {
                if let p = prev[pid], t >= p {
                    out[pid] = min(1.0, Double(t - p) / wall)
                }
            }
        }
        prev = totals
        prevAt = now
        return out
    }
}
