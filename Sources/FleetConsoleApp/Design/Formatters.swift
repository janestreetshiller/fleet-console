import Foundation

// Console formatting — window-precise counterparts to `SystemFmt` (popover) and
// `Fmt` (shared with the CLI).
//
// The window shows numbers a popover never would: full-precision byte counts,
// per-second rates with a decimal, load averages, latencies. All of them are
// formatted in exactly one place, so "1.42 GB/s" cannot render three different
// ways across three modules. Everything here pairs with `.monospacedDigit()`
// at the call site — a formatter cannot enforce that, the view must.

enum ConsoleFmt {
    private static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    // MARK: Bytes

    /// "994.66 GB" — the full-precision count for capacities and totals.
    static func bytes(_ value: Int64) -> String {
        bytes.string(fromByteCount: value)
    }

    /// "1.42 GB/s" for live throughput; nil is a genuine "not sampled" em dash,
    /// and sub-KB rates floor at zero rather than implying precision they lack.
    static func byteRate(_ value: Double?) -> String {
        guard let value, value >= 1024 else { return value == nil ? "—" : "0 KB/s" }
        return bytes.string(fromByteCount: Int64(value)) + "/s"
    }

    // MARK: Rates and ratios

    /// One-decimal percentage for process CPU ("37.4%"), where Activity
    /// Monitor parity matters. Whole percentages are reserved for utilisation
    /// tiles, where the decimal would claim precision a 2 s average lacks.
    static func cpuPercent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    static func utilPercent(_ share: Double?) -> String {
        guard let share else { return "—" }
        return "\(Int((share * 100).rounded()))%"
    }

    /// Load averages: two decimals, always, so columns align.
    static func load(_ values: [Double]) -> String {
        values.map { String(format: "%.2f", $0) }.joined(separator: "  ")
    }

    /// "12 ms" / "0.8 ms" — latency with one significant decimal under 10.
    static func latency(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        return ms < 10 ? String(format: "%.1f ms", ms) : String(format: "%.0f ms", ms)
    }

    // MARK: Processes

    /// PIDs are identifiers, not quantities: no grouping separators, ever.
    static func pid(_ pid: Int32?) -> String {
        pid.map(String.init) ?? "—"
    }

    static func port(_ port: Int) -> String { ":\(port)" }

    static func ports(_ ports: [Int]) -> String {
        ports.isEmpty ? "—" : ports.sorted().map { ":\($0)" }.joined(separator: "  ")
    }

    /// Thread/user-time pair from `proc_taskinfo`, seconds with one decimal.
    static func cpuTime(_ nanoseconds: UInt64) -> String {
        let seconds = Double(nanoseconds) / 1_000_000_000
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let minutes = Int(seconds) / 60
        return String(format: "%dm %04.1fs", minutes, seconds.truncatingRemainder(dividingBy: 60))
    }

    // MARK: Clock

    private static let timeOfDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Event-log timestamps. Twenty-four hour, seconds included, because the
    /// event log is where ordering disputes get settled.
    static func timestamp(_ date: Date) -> String {
        timeOfDay.string(from: date)
    }
}
