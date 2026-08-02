import Foundation

// Formatting shared by the CLI and the UI, so a duration or a byte count reads
// the same in `fleetctl list` as it does in the window.
// MARK: - Formatting helpers shared by CLI and UI

public enum Fmt {
    public static func duration(_ seconds: TimeInterval, compact: Bool = true) -> String {
        let s = Int(abs(seconds.rounded()))
        if s < 60 { return "\(s)s" }
        let m = s / 60, h = m / 60, d = h / 24
        if m < 60 { return compact ? "\(m)m" : "\(m)m \(s % 60)s" }
        if h < 24 { return compact ? "\(h)h \(m % 60)m" : "\(h)h \(m % 60)m" }
        return "\(d)d \(h % 24)h"
    }

    public static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "never" }
        let delta = now.timeIntervalSince(date)
        if delta < -1 { return "in \(duration(-delta))" }
        if delta < 2 { return "just now" }
        return "\(duration(delta)) ago"
    }

    public static func ports(_ ports: [Int]) -> String {
        ports.isEmpty ? "—" : ports.sorted().map { ":\($0)" }.joined(separator: " ")
    }

    /// The same list, capped, for rows where the ports are one accessory among
    /// several. Every accessory in a row is `fixedSize`, so a three-port service
    /// claims its full width unconditionally and the row takes it out of the only
    /// compressible thing left — the title. The Services popover drew a claimed,
    /// expired service as an icon, "Claimed", "Expired" and ":8080 :8081 :8082"
    /// with no name at all. The full list is still in the row's detail.
    public static func ports(_ ports: [Int], limit: Int) -> String {
        guard !ports.isEmpty else { return "—" }
        let sorted = ports.sorted()
        guard sorted.count > limit else { return sorted.map { ":\($0)" }.joined(separator: " ") }
        let shown = sorted.prefix(limit).map { ":\($0)" }.joined(separator: " ")
        return "\(shown) +\(sorted.count - limit)"
    }

    public static func mem(_ mb: Double?) -> String {
        guard let mb else { return "—" }
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }

    public static func cpu(_ pct: Double?) -> String {
        guard let pct else { return "—" }
        return String(format: "%.1f%%", pct)
    }
}
