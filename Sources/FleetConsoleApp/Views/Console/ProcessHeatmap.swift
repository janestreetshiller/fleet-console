import SwiftUI
import FleetCore

// The process map: what is actually on the machine, as areas.
//
// The successor to the original operations map, rebuilt on the shared
// squarified engine with three concrete improvements:
//
//   * **Every byte is accounted for.** The old map drew its top 40 groups and
//     silently dropped the rest; the tail now rolls into an "Other processes"
//     tile, so the map's areas sum to the resident total it claims to show.
//   * **Tiles act.** Tapping a tile selects its heaviest process in the
//     Processes module and opens its inspector — the map is a way in, not
//     just a picture.
//   * **Grouping is honest about what it folds.** Helpers are collapsed onto
//     their parent app (Activity Monitor's rule), and the tile's detail line
//     says how many processes the tile represents.
//
// Encoding is unchanged because it was right: area is resident memory, colour
// is CPU activity. Size is the market cap, colour is the day's move — the tile
// that is both large *and* red is the one to act on.

enum ProcessHeatmap {
    /// One tile per app group. Pure and nonisolated so the view body stays a
    /// projection; called with the inventory's current rows.
    static func items(from rows: [ProcessRow]) -> [HeatmapItem] {
        struct Group {
            var bytes: Int64 = 0
            var cpu: Double = 0
            var count: Int = 0
            var heaviestPID: Int32 = 0
            var heaviestBytes: Int64 = 0
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
            }
            groups[name] = group
            totalBytes += row.residentBytes
        }

        // Below 8 MB a group is texture at this zoom level; its bytes still
        // count toward the remainder tile.
        var kept = groups.filter { $0.value.bytes > 8_000_000 }
            .sorted { $0.value.bytes > $1.value.bytes }
        var counted = kept.reduce(Int64(0)) { $0 + $1.value.bytes }

        // Forty tiles is the most a map can show before the smallest becomes
        // a sliver. The tail is rolled up, not dropped.
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
                action: .selectPID(group.heaviestPID))
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
                // The remainder is a *quantity with no CPU story*, which is
                // exactly what the neutral tone means — it went through the same
                // axis as every other tile rather than around it.
                color: StatusTone.neutral.color,
                labelColor: StatusTone.neutral.tileLabelColor,
                isRemainder: true))
        }
        return items
    }

    /// Collapses "Foo Helper (Renderer)" and friends onto "Foo" — the app is
    /// the thing you act on, its fifteen helper processes are not fifteen
    /// tiles.
    static func foldedName(_ name: String) -> String {
        var folded = name
        for suffix in [" Helper (Renderer)", " Helper (GPU)", " Helper (Plugin)", " Helper"]
        where folded.hasSuffix(suffix) {
            folded = String(folded.dropLast(suffix.count))
        }
        return folded.isEmpty ? name : folded
    }
}

// MARK: - Label contrast on tone colours

extension StatusTone {
    /// In-tile label colour for a tile filled with this tone's colour.
    var tileLabelColor: Color {
        switch self {
        case .good, .bad, .neutral: return .white
        case .warn, .unknown: return .black
        }
    }
}
