import Foundation

final class SharedByteFormatter: @unchecked Sendable {
    private let lock = NSLock()
    private let formatter: ByteCountFormatter

    init(countStyle: ByteCountFormatter.CountStyle) {
        let formatter = ByteCountFormatter()
        formatter.countStyle = countStyle
        formatter.allowsNonnumericFormatting = false
        self.formatter = formatter
    }

    func string(fromByteCount value: Int64) -> String {
        lock.withLock { formatter.string(fromByteCount: value) }
    }
}

enum ConsoleFmt {
    private static let byteFormatter = SharedByteFormatter(countStyle: .file)

    static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }

    static func byteRate(_ value: Double?) -> String {
        guard let value, value >= 1024 else { return value == nil ? "—" : "0 KB/s" }
        return byteFormatter.string(fromByteCount: Int64(value)) + "/s"
    }

    static func cpuPercent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    static func utilPercent(_ share: Double?) -> String {
        guard let share else { return "—" }
        return "\(Int((share * 100).rounded()))%"
    }

    static func load(_ values: [Double]) -> String {
        values.map { String(format: "%.2f", $0) }.joined(separator: "  ")
    }

    static func latency(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        return ms < 10 ? String(format: "%.1f ms", ms) : String(format: "%.0f ms", ms)
    }

    static func pid(_ pid: Int32?) -> String {
        pid.map(String.init) ?? "—"
    }

    static func port(_ port: Int) -> String { ":\(port)" }

    static func ports(_ ports: [Int]) -> String {
        ports.isEmpty ? "—" : ports.sorted().map { ":\($0)" }.joined(separator: "  ")
    }

    static func cpuTime(_ nanoseconds: UInt64) -> String {
        let seconds = Double(nanoseconds) / 1_000_000_000
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let minutes = Int(seconds) / 60
        return String(format: "%dm %04.1fs", minutes, seconds.truncatingRemainder(dividingBy: 60))
    }

    private static let timeOfDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func timestamp(_ date: Date) -> String {
        timeOfDay.string(from: date)
    }
}
