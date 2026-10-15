import Foundation

/// Fixed-capacity FIFO. Appends are O(1) and never reallocate after warm-up.
public struct RingBuffer<Element>: Sequence {
    public let capacity: Int
    private var storage: [Element] = []
    private var head = 0                 // index of the oldest element once full

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func append(_ e: Element) {
        if storage.count < capacity { storage.append(e) }
        else { storage[head] = e; head = (head + 1) % capacity }
    }

    public var last: Element? {
        guard !storage.isEmpty else { return nil }
        return storage.count < capacity ? storage.last : storage[(head + capacity - 1) % capacity]
    }

    public var first: Element? {
        guard !storage.isEmpty else { return nil }
        return storage.count < capacity ? storage.first : storage[head]
    }

    /// Oldest → newest.
    public var elements: [Element] {
        storage.count < capacity ? storage : Array(storage[head...] + storage[..<head])
    }

    public mutating func removeAll() { storage.removeAll(keepingCapacity: true); head = 0 }

    public func makeIterator() -> IndexingIterator<[Element]> { elements.makeIterator() }
}

public struct TimedValue: Sendable, Hashable {
    public let date: Date
    public let value: Double
    public init(_ date: Date, _ value: Double) { self.date = date; self.value = value }
}

/// Two resolutions: every raw sample for the last few minutes, plus 30-second averages for an hour.
public struct MetricHistory {
    public private(set) var fine: RingBuffer<TimedValue>
    public private(set) var coarse: RingBuffer<TimedValue>
    private let bucket: TimeInterval
    private var bucketStart: Date?
    private var bucketSum = 0.0
    private var bucketCount = 0
    public private(set) var peak = 0.0
    private var sum = 0.0
    private var samples = 0

    public init(fineCapacity: Int = 150, coarseCapacity: Int = 120, bucket: TimeInterval = 30) {
        fine = RingBuffer(capacity: fineCapacity)
        coarse = RingBuffer(capacity: coarseCapacity)
        self.bucket = bucket
    }

    public mutating func append(_ value: Double, at date: Date) {
        let v = value.isFinite ? value : 0
        fine.append(TimedValue(date, v))
        peak = max(peak, v); sum += v; samples += 1
        if let start = bucketStart, date.timeIntervalSince(start) >= bucket {
            coarse.append(TimedValue(start.addingTimeInterval(bucket / 2), bucketSum / Double(max(bucketCount, 1))))
            bucketStart = date; bucketSum = 0; bucketCount = 0
        }
        if bucketStart == nil { bucketStart = date }
        bucketSum += v; bucketCount += 1
    }

    /// Mean since Pulse started.
    public var average: Double { samples > 0 ? sum / Double(samples) : 0 }
    public var latest: Double { fine.last?.value ?? 0 }

    /// Points for a chart window. Uses coarse data plus the live tail for windows longer than the fine buffer.
    public func points(last window: TimeInterval, now: Date = Date()) -> [TimedValue] {
        let cutoff = now.addingTimeInterval(-window)
        let f = fine.elements
        if let oldest = f.first, oldest.date <= cutoff { return f.filter { $0.date >= cutoff } }
        let firstFine = f.first?.date ?? now
        return coarse.elements.filter { $0.date >= cutoff && $0.date < firstFine } + f
    }

    /// Plain values (oldest → newest) for sparklines.
    public var recentValues: [Double] { fine.elements.map(\.value) }
}
