import Foundation
import FleetCore

/// The volume picture the reclaim catalogue cannot give you.
///
/// `StorageScanner` answers "what can I safely delete?". This answers the
/// question you ask first: "where did the disk go?" The two are deliberately
/// separate scans — the catalogue is a list of known caches, the breakdown is
/// a bounded survey of fixed top-level buckets, and neither guesses from
/// directory names.
///
/// Honesty rules, applied:
///   * The "System & Other" segment is *arithmetic*, not a measurement —
///     consumed minus everything measured, and minus purgeable. Its label says
///     exactly that.
///   * "Purgeable" is the APFS difference between `availableCapacity` and
///     `availableCapacityForImportantUsage` — what the system believes it can
///     claw back under pressure — never a scan result. It is *inside* consumed
///     space, so it is subtracted out of "System & Other" rather than added
///     alongside it: the segments must sum to the volume, not to more.
///   * Buckets are measured with allocated size (what the volume actually
///     gets back), same as the reclaim catalogue.

// MARK: - Volumes

struct VolumeInfo: Identifiable, Equatable {
    let id: String            // mount path — stable and unique per mount
    var name: String
    var mountPath: String
    var totalBytes: Int64
    var availableBytes: Int64
    /// Space macOS counts as reclaimable under pressure (local snapshots,
    /// caches, iCloud evictions). Included in `availableForImportantUsage`.
    var purgeableBytes: Int64
    var isInternal: Bool
    var isRoot: Bool
    var isEjectable: Bool
    var fileSystemType: String

    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    var usedShare: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
}

// MARK: - Breakdown

struct BreakdownSegment: Identifiable, Equatable {
    let id: String
    var category: StorageCategory
    var bytes: Int64
    /// Where the number came from, shown verbatim in the UI.
    var basis: String
}

struct StorageBreakdownResult: Equatable {
    var volumeID: String = "/"
    /// The root volume's capacity *as read for this scan*. The bar divides by
    /// this rather than by today's volume reading, so the segments and their
    /// denominator always come from the same moment. Zero means the volume
    /// could not be read at all — see `capacityKnown`.
    var volumeTotalBytes: Int64 = 0
    var segments: [BreakdownSegment] = []
    /// One tile per surveyed directory — the heatmap behind the bar. Only the
    /// measured buckets appear here; "System & Other" stays honestly unmappable.
    var diskMap: [DiskMapEntry] = []
    var scannedAt: Date?
    var scanning = false

    var measuredBytes: Int64 {
        segments.filter { $0.category != .other && $0.category != .purgeable && $0.category != .free }
            .reduce(0) { $0 + $1.bytes }
    }

    /// False when the scan ran without a readable root volume: there is then no
    /// free, purgeable or "System & Other" segment, and the bar has to say the
    /// buckets are all it covers instead of implying they cover the disk.
    var capacityKnown: Bool { volumeTotalBytes > 0 }
}

/// One tile in the disk heatmap: a directory the scanner actually walked.
struct DiskMapEntry: Identifiable, Equatable {
    let id: String            // path (or bucket root + "/.remainder")
    var name: String
    var path: String
    var category: StorageCategory
    var bytes: Int64
    /// True for the per-bucket roll-up tile (small entries, loose files, the
    /// capped tail). The map accounts for every measured byte — a tile that
    /// silently drops the tail would imply the bucket is tidier than it is.
    var isRemainder: Bool
}

// MARK: - Scanner

@Observable
@MainActor
final class StorageBreakdown {
    private(set) var volumes: [VolumeInfo] = []
    private(set) var breakdown = StorageBreakdownResult()
    private(set) var snapshots: [String] = []
    private(set) var snapshotsNote: String?

    private let queue = DispatchQueue(label: "com.fleetconsole.app.breakdown")

    init() {
        refreshVolumes()
    }

    // MARK: Volumes

    /// Mounted local volumes with real capacity figures. Cheap (resource values,
    /// no I/O walk), so it runs on demand from the module and on launch.
    func refreshVolumes() {
        queue.async { [weak self] in
            let found = Self.readVolumes()
            Task { @MainActor in
                guard let self else { return }
                if self.volumes != found { self.volumes = found }
            }
        }
    }

    nonisolated private static func readVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey,
            .volumeIsEjectableKey, .volumeIsLocalKey, .volumeIsRootFileSystemKey,
            .volumeIsReadOnlyKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []

        var volumes: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal == true,
                  let total = values.volumeTotalCapacity, total > 0 else { continue }
            let available = Int64(values.volumeAvailableCapacity ?? 0)
            let important = values.volumeAvailableCapacityForImportantUsage ?? 0
            let path = url.path
            volumes.append(VolumeInfo(
                id: path,
                name: values.volumeName ?? url.lastPathComponent,
                mountPath: path,
                totalBytes: Int64(total),
                availableBytes: available,
                purgeableBytes: max(0, important - available),
                isInternal: values.volumeIsInternal == true,
                isRoot: values.volumeIsRootFileSystem == true,
                isEjectable: values.volumeIsEjectable == true,
                fileSystemType: Self.fileSystemType(of: path)))
        }
        // Root first, then internal, then by name — the order About This Mac uses.
        return volumes.sorted {
            ($0.isRoot ? 0 : $0.isInternal ? 1 : 2, $0.name) < ($1.isRoot ? 0 : $1.isInternal ? 1 : 2, $1.name)
        }
    }

    /// `statfs` f_fstypename — "apfs", "hfs", "exfat"… — without parsing mount(8).
    nonisolated private static func fileSystemType(of path: String) -> String {
        var buffer = statfs()
        guard statfs(path, &buffer) == 0 else { return "unknown" }
        return withUnsafePointer(to: &buffer.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                String(cString: $0)
            }
        }
    }

    // MARK: Breakdown scan

    /// Measures the fixed buckets for the root volume. On demand only — this
    /// walks real directories and costs real I/O, so like the reclaim scan it
    /// never runs on a timer.
    func scan() {
        guard !breakdown.scanning else { return }
        breakdown.scanning = true
        queue.async { [weak self] in
            // Capacity is re-read here rather than taken from `volumes`:
            // `refreshVolumes` publishes back through the main actor, so a
            // caller that refreshed and scanned in the same turn would have
            // measured System & Other / Purgeable / Free against the *previous*
            // snapshot. Reading both on this hop makes the scan and its
            // capacity one fact, published together.
            let found = Self.readVolumes()
            let result = Self.measure(root: found.first { $0.isRoot })
            Task { @MainActor in
                guard let self else { return }
                if self.volumes != found { self.volumes = found }
                self.breakdown = result
                self.breakdown.scanning = false
            }
        }
    }

    /// The fixed survey: category, where it lives, and the one-line basis the
    /// inspector shows verbatim. A catalogue rather than a heuristic, for the
    /// same reason the reclaim catalogue is one.
    private struct BucketSpec {
        let category: StorageCategory
        let relative: [String]
        let absolute: [String]
        let basis: String
    }

    nonisolated private static func measure(root: VolumeInfo?) -> StorageBreakdownResult {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let specs: [BucketSpec] = [
            BucketSpec(category: .apps, relative: ["Applications"], absolute: ["/Applications"],
                       basis: "/Applications and ~/Applications, allocated size"),
            BucketSpec(category: .developer, relative: ["Library/Developer"], absolute: [],
                       basis: "~/Library/Developer — Xcode, simulators, toolchains"),
            BucketSpec(category: .caches, relative: ["Library/Caches", ".cache"], absolute: [],
                       basis: "~/Library/Caches and ~/.cache, allocated size"),
            BucketSpec(category: .documents, relative: ["Documents", "Desktop"], absolute: [],
                       basis: "~/Documents and ~/Desktop, allocated size"),
            BucketSpec(category: .downloads, relative: ["Downloads"], absolute: [],
                       basis: "~/Downloads, allocated size"),
            BucketSpec(category: .media, relative: ["Movies", "Music", "Pictures"], absolute: [],
                       basis: "~/Movies, ~/Music and ~/Pictures, allocated size"),
        ]

        func resolve(_ spec: BucketSpec) -> [String] {
            (spec.relative.map { (home as NSString).appendingPathComponent($0) } + spec.absolute)
                .filter { FileManager.default.fileExists(atPath: $0) }
        }

        var segments: [BreakdownSegment] = []
        var diskMap: [DiskMapEntry] = []
        for spec in specs {
            let paths = resolve(spec)
            let total = paths.reduce(Int64(0)) { $0 + StorageScanner.allocatedSize(of: $1) }
            // Sub-megabyte buckets are noise in a chart about gigabytes; their
            // bytes stay honestly accounted for inside "System & Other".
            guard total >= 1_000_000 else { continue }
            segments.append(BreakdownSegment(id: spec.category.id, category: spec.category,
                                             bytes: total, basis: spec.basis))
            diskMap.append(contentsOf: childrenSizes(of: paths, category: spec.category,
                                                     bucketTotal: total))
        }

        var result = StorageBreakdownResult(volumeID: "/",
                                            volumeTotalBytes: root?.totalBytes ?? 0,
                                            segments: segments,
                                            diskMap: diskMap, scannedAt: Date())
        if let root {
            // The three arithmetic segments, sized so that measured + other +
            // purgeable + free == totalBytes exactly. `availableBytes` is
            // `volumeAvailableCapacity`, which already excludes purgeable, so
            // purgeable lives inside `usedBytes`: adding it alongside Free and a
            // full-size Other would count it twice and ask the bar to draw more
            // than the volume holds. It is taken out of the unmeasured share
            // instead, and clamped to it so Other can never go negative.
            let unmeasured = max(0, root.usedBytes - segments.reduce(Int64(0)) { $0 + $1.bytes })
            let purgeable = min(root.purgeableBytes, unmeasured)
            result.segments.append(BreakdownSegment(
                id: StorageCategory.other.id, category: .other,
                bytes: unmeasured - purgeable,
                basis: "arithmetic, not a scan — used space minus everything measured above, "
                     + "minus purgeable. System data, other user accounts, and folders outside "
                     + "the surveyed buckets."))
            result.segments.append(BreakdownSegment(
                id: StorageCategory.purgeable.id, category: .purgeable,
                bytes: purgeable,
                basis: "APFS purgeable space — the gap between available and important-usage capacity. "
                     + "Local snapshots and caches the system reclaims under pressure. Counted as "
                     + "used space, not added on top of it."))
            result.segments.append(BreakdownSegment(
                id: StorageCategory.free.id, category: .free,
                bytes: root.availableBytes,
                basis: "Available now, with purgeable space excluded."))
        }
        return result
    }

    /// Measures the immediate children of a bucket — one tile per directory.
    /// The walk is the same enumeration the bucket total already paid for, so
    /// the heatmap adds listing cost only, not another disk traversal.
    ///
    /// Two honest caps: entries under 4 MB roll into the bucket's remainder
    /// tile (they are texture, not signal at this zoom level), and a bucket
    /// keeps at most 24 tiles before its tail joins the remainder — a heatmap
    /// with 300 slivers answers no question the row above it didn't.
    nonisolated private static func childrenSizes(of paths: [String], category: StorageCategory,
                                                  bucketTotal: Int64) -> [DiskMapEntry] {
        var entries: [DiskMapEntry] = []
        var counted: Int64 = 0

        for rootPath in paths {
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: rootPath)
            else { continue }
            for child in children {
                let childPath = (rootPath as NSString).appendingPathComponent(child)
                let bytes = StorageScanner.allocatedSize(of: childPath)
                guard bytes > 4_000_000 else { continue }
                entries.append(DiskMapEntry(id: childPath, name: child, path: childPath,
                                            category: category, bytes: bytes, isRemainder: false))
                counted += bytes
            }
        }

        entries.sort { $0.bytes > $1.bytes }
        if entries.count > 24 {
            counted -= entries[24...].reduce(Int64(0)) { $0 + $1.bytes }
            entries.removeSubrange(24...)
        }

        // Everything the tiles did not claim: small entries, loose files at
        // the bucket root, and the capped tail. Drawn as its own tile so the
        // map's areas sum to the segment above it.
        let remainder = bucketTotal - counted
        if remainder > 4_000_000, let first = paths.first {
            entries.append(DiskMapEntry(id: first + "/.remainder", name: "Other",
                                        path: first, category: category,
                                        bytes: remainder, isRemainder: true))
        }
        return entries
    }

    // MARK: APFS local snapshots

    /// Local Time Machine snapshots are the most common reason "purgeable" is
    /// tens of gigabytes. Listed read-only via `tmutil`; without permission the
    /// note says why the list is empty instead of implying there are none.
    func loadSnapshots(for volume: VolumeInfo) {
        queue.async { [weak self] in
            guard let tmutil = Shell.which("tmutil", candidates: ["/usr/bin/tmutil"]) else { return }
            let result = Shell.run(tmutil, ["listlocalsnapshots", volume.mountPath], timeout: 15)
            let names = result.stdout.split(separator: "\n")
                .map(String.init)
                .filter { $0.contains("com.apple.TimeMachine.") }
                .map { $0.replacingOccurrences(of: "com.apple.TimeMachine.", with: "") }
                .sorted()
            Task { @MainActor in
                guard let self else { return }
                if result.succeeded {
                    self.snapshots = names
                    self.snapshotsNote = names.isEmpty ? "No local snapshots on \(volume.name)." : nil
                } else {
                    self.snapshots = []
                    self.snapshotsNote = "tmutil could not list snapshots — "
                        + (result.stderr.split(separator: "\n").first.map(String.init)
                           ?? "permission was denied")
                }
            }
        }
    }
}
