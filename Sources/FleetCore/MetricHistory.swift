import Foundation

public struct MetricSample: Identifiable, Equatable, Sendable {
    public let time: Date
    public let value: Double
    public var id: Date { time }

    public init(time: Date, value: Double) {
        self.time = time
        self.value = value
    }
}

/// Actual observation times survive delayed ticks and manual refreshes.
/// No averaging: a single observation at a peak remains in the plotted series.
public struct MetricHistory: Sendable {
    public private(set) var samples: [MetricSample] = []
    public let retention: TimeInterval
    public let capacity: Int

    public init(retention: TimeInterval = 120, capacity: Int = 512) {
        precondition(retention > 0 && retention.isFinite && capacity > 1)
        self.retention = retention
        self.capacity = capacity
    }

    public mutating func append(_ value: Double, at time: Date) {
        guard value.isFinite, time.timeIntervalSince1970.isFinite else { return }
        if let last = samples.last {
            guard time >= last.time else { return }
            if time == last.time { samples.removeLast() }
        }
        samples.append(MetricSample(time: time, value: value))
        let cutoff = time.addingTimeInterval(-retention)
        samples.removeAll { $0.time < cutoff }
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    public func visible(in range: ClosedRange<Date>) -> [MetricSample] {
        samples.filter { range.contains($0.time) }
    }
}

public enum ChartTimeWindow: Int, CaseIterable, Sendable {
    case seconds15 = 15, seconds30 = 30, minute = 60, minutes2 = 120
    public var label: String {
        switch self {
        case .seconds15: return "15 s"
        case .seconds30: return "30 s"
        case .minute: return "1 min"
        case .minutes2: return "2 min"
        }
    }
    public func range(endingAt time: Date) -> ClosedRange<Date> {
        time.addingTimeInterval(-Double(rawValue))...time
    }
}
