import Foundation

/// Human-readable formatting. Pure functions, unit-tested.
public enum Format {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    /// Binary (1024) units, matching Activity Monitor's memory column. `compact` drops a trailing ".0".
    public static func bytes<T: BinaryInteger>(_ value: T, compact: Bool = false) -> String {
        var (n, u) = split(Double(value), base: 1024)
        if compact, n.hasSuffix(".0") { n.removeLast(2) }
        return n + " " + u
    }

    /// Decimal (1000) units per second, matching Finder/network conventions.
    public static func rate(_ bytesPerSecond: Double) -> String {
        let (n, u) = split(max(0, bytesPerSecond), base: 1000)
        return "\(n) \(u)/s"
    }

    /// Returns (number, unit), e.g. 1.5 GB → ("1.5", "GB"). Bytes are shown without decimals.
    public static func split(_ value: Double, base: Double) -> (String, String) {
        var v = max(0, value)
        var i = 0
        while v >= base * 0.995, i < units.count - 1 { v /= base; i += 1 }
        if i == 0 { return (String(Int(v.rounded())), "B") }
        let digits = v >= 100 ? 0 : 1
        return (String(format: "%.\(digits)f", v), units[i])
    }

    public static func bytesParts<T: BinaryInteger>(_ value: T) -> (String, String) { split(Double(value), base: 1024) }
    public static func rateParts(_ value: Double) -> (String, String) {
        let (n, u) = split(value, base: 1000)
        return (n, u + "/s")
    }

    /// 0…1 → "42%"
    public static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }
    public static func percentNumber(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))" }

    /// CPU in "percent of one core" → share of the whole machine with one decimal, e.g. "3.4%".
    public static func cpuShare(_ percentOfCore: Double, cores: Int = Hardware.cores) -> String {
        let v = percentOfCore / Double(max(cores, 1))
        return v >= 10 ? "\(Int(v.rounded()))%" : String(format: "%.1f%%", v)
    }

    /// "3d 4h", "2h 5m", "12 min"
    public static func duration(_ t: TimeInterval) -> String {
        let s = Int(max(0, t))
        let d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(max(m, 1)) min"
    }

    /// "1h 05m" style for battery time remaining.
    public static func minutes(_ m: Int) -> String {
        m >= 60 ? String(format: "%dh %02dm", m / 60, m % 60) : "\(m) min"
    }
}
