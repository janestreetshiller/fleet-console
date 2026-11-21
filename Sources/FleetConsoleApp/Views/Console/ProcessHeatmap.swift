import SwiftUI
import FleetCore

enum ProcessHeatmap {
    static func items(from rows: [ProcessRow]) -> [HeatmapItem] {
        struct Group {
            var bytes: Int64 = 0
            var cpu: Double = 0
            var count: Int = 0
            var heaviestPID: Int32 = 0
            var heaviestBytes: Int64 = 0
            var startSignature: String?
        }

        var groups: [String: Group] = [:]
        var totalBytes: Int64 = 0
        for row in rows {
            let name = foldedName(row.name)
            var group = groups[name] ?? Group()
            group.bytes += row.residentBytes
            group.cpu += row.cpuPercent
            group.count += 1
            if row.residentBytes > group.heaviestBytes {
                group.heaviestBytes = row.residentBytes
                group.heaviestPID = row.pid
                group.startSignature = row.startSignature
            }
            groups[name] = group
            totalBytes += row.residentBytes
        }

        var kept = groups.filter { $0.value.bytes > 8_000_000 }
            .sorted { $0.value.bytes > $1.value.bytes }
        var counted = kept.reduce(Int64(0)) { $0 + $1.value.bytes }

        if kept.count > 40 {
            counted -= kept[40...].reduce(Int64(0)) { $0 + $1.value.bytes }
            kept.removeSubrange(40...)
        }

        var items = kept.map { name, group -> HeatmapItem in
            let tone = SystemThresholds.cpuActivity(percent: group.cpu)
            return HeatmapItem(
                id: name,
                name: name,
                detail: group.count == 1
                    ? "1 process · CPU \(ConsoleFmt.cpuPercent(group.cpu))"
                    : "\(group.count) processes · CPU \(ConsoleFmt.cpuPercent(group.cpu))",
                bytes: group.bytes,
                color: tone.color,
                labelColor: tone.tileLabelColor,
                action: .selectPID(group.heaviestPID), processStartSignature: group.startSignature)
        }

        let remainder = totalBytes - counted
        if remainder > 8_000_000 {
            let foldedCount = groups.count - kept.count
            items.append(HeatmapItem(
                id: "remainder",
                name: "Other",
                detail: foldedCount == 1
                    ? "1 smaller app or helper"
                    : "\(foldedCount) smaller apps and helpers",
                bytes: remainder,
                color: StatusTone.neutral.color,
                labelColor: StatusTone.neutral.tileLabelColor,
                isRemainder: true))
        }
        return items
    }

    static func foldedName(_ name: String) -> String {
        var folded = name
        for suffix in [" Helper (Renderer)", " Helper (GPU)", " Helper (Plugin)", " Helper"]
        where folded.hasSuffix(suffix) {
            folded = String(folded.dropLast(suffix.count))
        }
        return folded.isEmpty ? name : folded
    }
}

extension StatusTone {
    var tileLabelColor: Color {
        switch self {
        case .good, .bad, .neutral: return .white
        case .warn, .unknown: return .black
        }
    }
}
