import Foundation
import FleetCore

struct VolumeInfo: Identifiable, Equatable {
    let id: String
    var name: String
    var mountPath: String
    var totalBytes: Int64
    var availableBytes: Int64
    var purgeableBytes: Int64
    var isInternal: Bool
    var isRoot: Bool
    var isEjectable: Bool
    var fileSystemType: String

    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    var usedShare: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
}

struct BreakdownSegment: Identifiable, Equatable {
    let id: String
    var category: StorageCategory
    var bytes: Int64
    var basis: String
}

struct StorageBreakdownResult: Equatable {
    var volumeID: String = "/"
    var volumeTotalBytes: Int64 = 0
    var segments: [BreakdownSegment] = []
    var diskMap: [DiskMapEntry] = []
    var scannedAt: Date?
    var scanning = false

    var measuredBytes: Int64 {
        segments.filter { $0.category != .other && $0.category != .purgeable && $0.category != .free }
            .reduce(0) { $0 + $1.bytes }
    }

    var capacityKnown: Bool { volumeTotalBytes > 0 }
}

struct DiskMapEntry: Identifiable, Equatable {
    let id: String
    var name: String
    var path: String
    var category: StorageCategory
    var bytes: Int64
    var isRemainder: Bool
}

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
        return volumes.sorted {
            ($0.isRoot ? 0 : $0.isInternal ? 1 : 2, $0.name) < ($1.isRoot ? 0 : $1.isInternal ? 1 : 2, $1.name)
        }
    }

    nonisolated private static func fileSystemType(of path: String) -> String {
        var buffer = statfs()
        guard statfs(path, &buffer) == 0 else { return "unknown" }
        return withUnsafePointer(to: &buffer.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                String(cString: $0)
            }
        }
    }

    func scan() {
        guard !breakdown.scanning else { return }
        breakdown.scanning = true
        queue.async { [weak self] in
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

        let remainder = bucketTotal - counted
        if remainder > 4_000_000, let first = paths.first {
            entries.append(DiskMapEntry(id: first + "/.remainder", name: "Other",
                                        path: first, category: category,
                                        bytes: remainder, isRemainder: true))
        }
        return entries
    }

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
