import Foundation
import AppKit
import Observation

/// Folder metadata follows the existing process-observation pulse. A root change
/// or explicit expansion cancels the obsolete scan; there is no extra timer.
@MainActor @Observable
final class DirectoryCrystalStore {
    struct Request: Hashable {
        let roots: [String]
        let expanded: [String]
        let required: [String]
        let revision: Int
    }

    private(set) var roots: [String]
    private var explicitlySelectedRoots: Set<String> = []
    private(set) var expanded: Set<String> = []
    private(set) var snapshot: DirectoryCrystal?
    private(set) var scanning = false
    private(set) var revision = 0
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let persistsSelection: Bool
    private static let preference = "directoryCrystal.roots.v1"

    init(roots: [String]? = nil) {
        persistsSelection = roots == nil
        if let roots {
            self.roots = Array(Set(roots)).sorted()
        } else if let saved = UserDefaults.standard.stringArray(forKey: Self.preference) {
            self.roots = Array(Set(saved)).sorted()
            self.explicitlySelectedRoots = Set(saved)
        } else {
            let code = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Code").path
            var isDirectory: ObjCBool = false
            self.roots = FileManager.default.fileExists(atPath: code, isDirectory: &isDirectory) && isDirectory.boolValue ? [code] : []
        }
    }

    func request(required: [String]) -> Request {
        Request(roots: roots, expanded: expanded.sorted(), required: Array(Set(required)).sorted(), revision: revision)
    }

    func load(required: [String]) async {
        let token = UUID()
        generation = token
        scanning = true
        defer { if generation == token { scanning = false } }
        let roots = roots
        let expanded = expanded
        let approved = explicitlySelectedRoots
        let operation = Task.detached(priority: .utility) {
            DirectoryCrystal.scan(roots: roots, expanded: expanded, requiredPaths: required,
                                  explicitlySelectedRoots: approved, isCancelled: { Task.isCancelled })
        }
        let value = await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }
        guard !Task.isCancelled, generation == token else { return }
        snapshot = value
    }

    func refreshIfNeeded(now: Date = Date()) {
        guard !scanning, let snapshot, now.timeIntervalSince(snapshot.scannedAt) >= 30 else { return }
        refresh()
    }

    func refresh() { revision &+= 1 }

    func toggleExpansion(_ path: String) {
        if !expanded.insert(path).inserted { expanded.remove(path) }
        refresh()
    }

    func chooseRoots() {
        let panel = NSOpenPanel()
        panel.title = "Directory roots"
        panel.message = "Choose folders to map. Only directory names and parent–child structure are read; hidden folders, generated caches and symbolic links are excluded."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = false
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            self.roots = Array(Set(panel.urls.map(\.path))).sorted()
            self.explicitlySelectedRoots = Set(self.roots)
            self.expanded = []
            self.snapshot = nil
            if self.persistsSelection { UserDefaults.standard.set(self.roots, forKey: Self.preference) }
            self.refresh()
        }
    }
}
