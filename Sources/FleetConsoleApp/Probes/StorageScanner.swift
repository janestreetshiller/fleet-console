import Foundation
import AppKit

/// Finds space worth reclaiming, and is careful about the difference between a
/// cache and your data.
///
/// The rule that shapes everything here: **a directory being large is not a reason
/// to delete it.** A local model weighs 7 GB and takes an hour to fetch again; a
/// package cache weighs 2 GB and comes back on its own the next time you build.
/// A cleaner that treats those the same is not a tool, it is a trap. So every
/// candidate declares what actually happens when it goes, and anything holding
/// real data is reported but never offered for deletion.
///
/// Nothing in this file deletes anything on its own. `reclaim(_:)` runs only when
/// something calls it, and the UI only calls it after an explicit confirmation
/// that names the paths and the consequence.

// MARK: - Model

struct ReclaimCandidate: Identifiable, Equatable {
    /// How much you lose by deleting it — not how large it is.
    enum Risk: Equatable {
        /// Regenerates transparently. Deleting costs you nothing but the next
        /// build being slightly slower.
        case safe
        /// Regenerates, but at a real cost in bandwidth or time.
        case review
        /// Not a cache. Reported so you can see where the disk went; never offered
        /// for deletion, because this tool does not delete your data.
        case keep

        var label: String {
            switch self {
            case .safe: return "regenerates"
            case .review: return "re-downloads"
            case .keep: return "your data"
            }
        }

        var tone: StatusTone {
            switch self {
            case .safe: return .good
            case .review: return .warn
            case .keep: return .neutral
            }
        }

        var reclaimable: Bool { self != .keep }
    }

    let id: String
    let title: String
    let icon: String
    let risk: Risk
    /// What happens after it is gone. Shown before anything is deleted.
    let consequence: String
    let paths: [String]
    var sizeBytes: Int64

    /// `safe` entries are removed outright, the way `brew cleanup` and
    /// `npm cache clean` already do. Anything that costs something to rebuild goes
    /// to the Trash instead, so a wrong call is recoverable — at the price of not
    /// freeing the space until the Trash is emptied. That trade is stated in the
    /// confirmation rather than decided quietly.
    var movesToTrash: Bool { risk == .review }
}

/// One entry in the catalogue, before it has been resolved against the disk.
private struct CandidateSpec {
    let id: String
    let title: String
    let icon: String
    let risk: ReclaimCandidate.Risk
    let consequence: String
    /// Paths relative to the home directory.
    let paths: [String]
}

// MARK: - Catalogue
//
// Deliberately a list of known things rather than a heuristic. A cleaner that
// guesses from directory names is how people lose work: `~/Library/Application
// Support/<some app>` is enormous on this machine and every byte of it matters.

private let catalogue: [CandidateSpec] = [
    // ── Package and build caches ────────────────────────────────────────────
    .init(id: "uv", title: "uv package cache", icon: "shippingbox", risk: .safe,
          consequence: "uv re-downloads wheels the next time you install. No project breaks.",
          paths: [".cache/uv"]),
    .init(id: "cargo", title: "Cargo registry cache", icon: "shippingbox", risk: .safe,
          consequence: "Cargo re-fetches crate sources on the next build.",
          paths: [".cargo/registry/cache", ".cargo/registry/src"]),
    .init(id: "npm", title: "npm cache", icon: "hexagon", risk: .safe,
          consequence: "npm re-downloads packages on the next install.",
          paths: [".npm/_cacache"]),
    .init(id: "homebrew", title: "Homebrew downloads", icon: "shippingbox", risk: .safe,
          consequence: "Bottles are re-downloaded next time you install or upgrade. Installed formulae are untouched.",
          paths: ["Library/Caches/Homebrew"]),
    .init(id: "node-gyp", title: "node-gyp headers", icon: "hexagon", risk: .safe,
          consequence: "Re-downloaded when a native module next compiles.",
          paths: ["Library/Caches/node-gyp"]),
    .init(id: "electron", title: "Electron build cache", icon: "shippingbox", risk: .safe,
          consequence: "Re-downloaded on the next Electron build.",
          paths: ["Library/Caches/electron", "Library/Caches/electron-builder"]),
    .init(id: "derived-data", title: "Xcode DerivedData", icon: "hammer", risk: .safe,
          consequence: "Xcode rebuilds indexes and intermediates. First build after this is slow.",
          paths: ["Library/Developer/Xcode/DerivedData"]),

    // ── System caches ──────────────────────────────────────────────────────
    .init(id: "wallpaper", title: "Aerial wallpaper videos", icon: "photo", risk: .safe,
          consequence: "macOS re-downloads a wallpaper only if you pick an aerial one again.",
          paths: ["Library/Application Support/com.apple.wallpaper/aerials"]),
    .init(id: "trash", title: "Trash", icon: "trash", risk: .safe,
          consequence: "Permanently removes what is already in the Trash.",
          paths: [".Trash"]),

    // ── Costly to rebuild ──────────────────────────────────────────────────
    .init(id: "huggingface", title: "Hugging Face model cache", icon: "brain", risk: .review,
          consequence: "These are model weights. They re-download on next use — potentially gigabytes over the network.",
          paths: [".cache/huggingface"]),
    .init(id: "spotify", title: "Spotify offline cache", icon: "music.note", risk: .review,
          consequence: "Offline playback data. Re-downloads when you next play those tracks; anything downloaded for offline use goes.",
          paths: ["Library/Caches/com.spotify.client"]),
    .init(id: "playwright", title: "Playwright browsers", icon: "globe", risk: .review,
          consequence: "Browser binaries. Re-downloaded by `playwright install`, roughly half a gigabyte.",
          paths: ["Library/Caches/ms-playwright"]),
    .init(id: "simulator", title: "iOS Simulator devices and caches", icon: "iphone", risk: .review,
          consequence: "Simulator devices and their contents. Xcode recreates devices, but their installed apps and state are lost.",
          paths: ["Library/Developer/CoreSimulator/Caches", "Library/Developer/CoreSimulator/Devices"]),
    .init(id: "pnpm", title: "pnpm store", icon: "hexagon", risk: .review,
          consequence: "The pnpm store is hard-linked into existing node_modules. Removing it breaks installed projects until you reinstall.",
          paths: ["Library/pnpm/store"]),
    .init(id: "codex-runtimes", title: "Codex runtimes", icon: "shippingbox", risk: .review,
          consequence: "Downloaded language runtimes. Re-fetched on next use.",
          paths: [".cache/codex-runtimes"]),

    // ── Reported, never offered ────────────────────────────────────────────
    .init(id: "data-models", title: "Local model and voice data", icon: "brain", risk: .keep,
          consequence: "Local model weights and voice data belonging to installed apps. This is data, not cache — FleetConsole will not delete it.",
          paths: ["Library/Application Support/Heavyweights LM",
                  "Library/Application Support/LocalAIVoice",
                  "Library/Application Support/Buzz"]),
]

// MARK: - Scan result

struct ReclaimScan: Equatable {
    var candidates: [ReclaimCandidate] = []
    var scannedAt: Date?
    var scanning = false

    var reclaimable: [ReclaimCandidate] { candidates.filter { $0.risk.reclaimable } }

    var reclaimableBytes: Int64 {
        reclaimable.reduce(0) { $0 + $1.sizeBytes }
    }

    var safeBytes: Int64 {
        candidates.filter { $0.risk == .safe }.reduce(0) { $0 + $1.sizeBytes }
    }
}

// MARK: - Scanner

@Observable
@MainActor
final class StorageScanner {
    private(set) var scan = ReclaimScan()
    /// Set when a reclaim partially failed — usually a path macOS protects.
    private(set) var lastError: String?
    private(set) var lastReclaimed: String?

    private let queue = DispatchQueue(label: "com.fleetconsole.app.reclaim")

    /// Walks the catalogue and measures what is actually on disk.
    ///
    /// Explicitly on demand. Measuring these trees costs real I/O, so it does not
    /// run on the sampling timer — a monitor that thrashes the disk to tell you the
    /// disk is busy is its own bug.
    func rescan() {
        guard !scan.scanning else { return }
        scan.scanning = true
        queue.async { [weak self] in
            let found = Self.measure()
            Task { @MainActor in
                guard let self else { return }
                self.scan.candidates = found
                self.scan.scannedAt = Date()
                self.scan.scanning = false
            }
        }
    }

    // The three helpers below do the actual filesystem work and are called from the
    // reclaim queue, never the main actor.
    nonisolated private static func measure() -> [ReclaimCandidate] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var results: [ReclaimCandidate] = []

        for spec in catalogue {
            let existing = spec.paths
                .map { (home as NSString).appendingPathComponent($0) }
                .filter { FileManager.default.fileExists(atPath: $0) }
            guard !existing.isEmpty else { continue }

            let size = existing.reduce(Int64(0)) { $0 + allocatedSize(of: $1) }
            // Anything under a megabyte is noise in a list about gigabytes.
            guard size > 1_000_000 else { continue }

            results.append(ReclaimCandidate(id: spec.id, title: spec.title, icon: spec.icon,
                                            risk: spec.risk, consequence: spec.consequence,
                                            paths: existing, sizeBytes: size))
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Sums allocated size, which is what the volume actually gets back — not
    /// logical file size, which overstates on a compressed or sparse tree.
    /// Shared with `StorageBreakdown`, which measures its buckets the same way.
    nonisolated static func allocatedSize(of path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys,
            options: [], errorHandler: { _, _ in true }) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: - Reclaim

    /// Deletes or trashes one candidate. Called only from an explicit confirmation.
    ///
    /// `keep` candidates are refused here as well as hidden in the UI, so a future
    /// caller cannot route around the rule by constructing the action itself.
    /// `completion` is `@MainActor` because that is where it has always been
    /// called from. Saying so makes it `Sendable`, which is what lets it cross
    /// onto `queue` and back.
    func reclaim(_ candidate: ReclaimCandidate, completion: @escaping @MainActor (Bool) -> Void) {
        guard candidate.risk.reclaimable else {
            lastError = "\(candidate.title) holds data, not cache — it is not reclaimable."
            completion(false)
            return
        }

        let paths = candidate.paths
        let toTrash = candidate.movesToTrash
        let title = candidate.title
        let freed = candidate.sizeBytes

        queue.async { [weak self] in
            var failures: [String] = []
            for path in paths {
                let url = URL(fileURLWithPath: path)
                do {
                    if toTrash {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    } else {
                        // Empty the directory rather than removing it: several of these
                        // are recreated by their owning tool only at install time, and a
                        // missing cache root is a worse failure than an empty one.
                        try Self.emptyDirectory(url)
                    }
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            Task { @MainActor in
                guard let self else { return }
                if failures.isEmpty {
                    self.lastError = nil
                    self.lastReclaimed = "Reclaimed \(SystemFmt.size(freed)) from \(title)"
                } else {
                    self.lastError = "Some items could not be removed — \(failures.joined(separator: "; "))"
                }
                completion(failures.isEmpty)
                self.rescan()
            }
        }
    }

    nonisolated private static func emptyDirectory(_ url: URL) throws {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        guard isDirectory.boolValue else {
            try manager.removeItem(at: url)
            return
        }
        for entry in try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            try manager.removeItem(at: entry)
        }
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
}
