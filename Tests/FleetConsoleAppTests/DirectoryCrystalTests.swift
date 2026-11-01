import Foundation
import Testing
@testable import FleetConsoleApp

struct DirectoryCrystalTests {
    private func fixture(_ body: (URL) throws -> Void) throws {
        let temporary = try #require(realpath(ProcessInfo.processInfo.environment["TMPDIR"] ?? FileManager.default.temporaryDirectory.path, nil))
        defer { free(temporary) }
        let root = URL(fileURLWithPath: String(cString: temporary)).appendingPathComponent("directory-crystal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func directory(_ path: String, in root: URL) throws -> String {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    @Test func expandedAndRequiredPathsWinTheBudgetAndExposeTwoMoreLevels() throws {
        try fixture { root in
            for i in 0..<610 { _ = try directory("a-filler/\(i)", in: root) }
            let selected = try directory("z-project/Sources/UI", in: root)
            let leaf = try directory("z-project/Sources/UI/Components/Views", in: root)
            let initial = DirectoryCrystal.scan(roots: [root.path])
            #expect(initial.nodes.count == 600)
            #expect(initial.truncated)
            let expanded = DirectoryCrystal.scan(roots: [root.path], expanded: [selected])
            #expect(expanded.nodes.contains { $0.path == leaf && $0.depth == 5 })
            #expect(expanded.nodes.count == 600)
            let required = DirectoryCrystal.scan(roots: [root.path], requiredPaths: [leaf, leaf + "/missing"], maxNodes: 6)
            #expect(required.nodes.contains { $0.path == leaf })
            #expect(!required.nodes.contains { $0.path.hasSuffix("/missing") })
            #expect(required.nodes.count == 6)
            let shallow = DirectoryCrystal.scan(roots: [root.path], maxDepth: 3)
            #expect(!shallow.nodes.contains { $0.path == leaf })
        }
    }

    @Test func priorityChainsAndExpansionWindowWinAcrossSaturatedRootsAndSiblings() throws {
        try fixture { root in
            let a = try directory("a", in: root)
            let z = try directory("z", in: root)
            let agent = try directory("a/agent", in: root)
            let selected = try directory("z/project/Sources/UI", in: root)
            let leaf = try directory("z/project/Sources/UI/Components/Views", in: root)
            for i in 0..<610 { _ = try directory("a/ordinary-\(i)", in: root) }
            let now = Date(timeIntervalSince1970: 19)
            let graph = DirectoryCrystal.scan(roots: [a, z], expanded: [selected], requiredPaths: [agent], now: now)
            #expect(graph.nodes.count == 600)
            #expect(graph.nodes.contains { $0.path == agent })
            #expect(graph.nodes.contains { $0.path == leaf && $0.depth == 5 })
            #expect(graph == DirectoryCrystal.scan(roots: [z, a], expanded: [selected], requiredPaths: [agent], now: now))
            let siblingAgent = try directory("z/agent/deep", in: root)
            let siblings = DirectoryCrystal.scan(roots: [root.path], requiredPaths: [agent, siblingAgent])
            #expect(siblings.nodes.count == 600)
            #expect(siblings.nodes.contains { $0.path == agent })
            #expect(siblings.nodes.contains { $0.path == siblingAgent })
            let missing = DirectoryCrystal.scan(roots: [a, z], expanded: [z + "/absent/deep"], requiredPaths: [a + "/missing/deep"])
            #expect(missing.nodes.count == 600)
            #expect(!missing.nodes.contains { $0.path.contains("/absent") || $0.path.contains("/missing") })
            let paths = Set(graph.nodes.map(\.path))
            #expect(graph.branches.allSatisfy { paths.contains($0.parent) && paths.contains($0.child) })
        }
    }

    @Test func layoutIsDeterministicUniqueAndContainsEveryNodeInBounds() throws {
        try fixture { root in
            let one = try directory("one/a/deep", in: root)
            let two = try directory("two/b", in: root)
            let firstRoot = (one as NSString).deletingLastPathComponent
            let otherRoot = (two as NSString).deletingLastPathComponent
            for i in 0..<18 { _ = try directory("one/a/sibling-\(i)/leaf", in: root) }
            let now = Date(timeIntervalSince1970: 17)
            let graph = DirectoryCrystal.scan(roots: [firstRoot, otherRoot, one], now: now)
            let permuted = DirectoryCrystal.scan(roots: [one, otherRoot, firstRoot, firstRoot], now: now)
            #expect(graph == permuted)
            #expect(Set(graph.nodes.map(\.id)).count == graph.nodes.count)
            #expect(Set(graph.nodes.map { "\($0.position.x),\($0.position.y)" }).count == graph.nodes.count)
            #expect(Set(graph.branches.map(\.id)).count == graph.branches.count)
            #expect(graph.nodes.allSatisfy { graph.bounds.contains($0.position) })
            #expect(graph.bounds.width > 0 && graph.bounds.height > 0)
            let byPath = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.path, $0) })
            for edge in graph.branches {
                let parent = try #require(byPath[edge.parent])
                let child = try #require(byPath[edge.child])
                let dx = child.position.x - parent.position.x
                let dy = child.position.y - parent.position.y
                #expect(abs(dy) < 0.0001 || abs(abs(dy) - abs(dx) * sqrt(3)) < 0.0001)
            }
            let sample = graph.nodes.filter { $0.rootPath == firstRoot }
            #expect(Set(sample.map { $0.position.y }).count > 2)
        }
    }

    @Test func neverFollowsEscapingSymlinksOrLoopsIncludingRoots() throws {
        try fixture { root in
            let inside = try directory("chosen/real", in: root)
            let outside = try directory("outside/secret", in: root)
            let chosen = (inside as NSString).deletingLastPathComponent
            try FileManager.default.createSymbolicLink(atPath: chosen + "/escape", withDestinationPath: outside)
            try FileManager.default.createSymbolicLink(atPath: chosen + "/loop", withDestinationPath: chosen)
            try FileManager.default.createSymbolicLink(atPath: root.path + "/root-link", withDestinationPath: chosen)
            let graph = DirectoryCrystal.scan(roots: [chosen])
            #expect(graph.nodes.count == 2)
            #expect(graph.nodes.first { $0.path == chosen }?.childDirectoryCount == 1)
            #expect(graph.nodes.allSatisfy { !$0.isSymbolicLink && $0.path.hasPrefix(chosen) })
            #expect(DirectoryCrystal.scan(roots: [root.path + "/root-link"]).nodes.isEmpty)
            #expect(DirectoryCrystal.scan(roots: [root.path + "/root-link/real"]).nodes.isEmpty)
            #expect(DirectoryCrystal.scan(roots: [chosen + "/../outside"]).nodes.isEmpty)
        }
    }

    @Test func cancellationUnreadableAndEntryBudgetsRemainHonest() throws {
        try fixture { root in
            let locked = try directory("locked", in: root)
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked) }
            let denied = DirectoryCrystal.scan(roots: [root.path])
            let node = try #require(denied.nodes.first { $0.path == locked })
            #expect(node.unreadable && node.truncated && node.childDirectoryCount == nil)
            #expect(denied.truncated)
            let cancelled = DirectoryCrystal.scan(roots: [root.path], isCancelled: { true })
            #expect(cancelled.truncated && cancelled.nodes.isEmpty)
            #expect(cancelled.issues.contains { $0.localizedCaseInsensitiveContains("cancelled") })
            let many = try directory("many", in: root)
            for i in 0..<12_010 {
                #expect(FileManager.default.createFile(atPath: many + "/f\(i)", contents: nil))
            }
            let partial = DirectoryCrystal.scan(roots: [many])
            #expect(partial.nodes.first?.childDirectoryCount == nil)
            #expect(partial.nodes.first?.truncated == true)
            #expect(partial.truncated && partial.issues.contains { $0.contains("12000") })
            var checks = 0
            let midScan = DirectoryCrystal.scan(roots: [many], isCancelled: { checks += 1; return checks > 20 })
            #expect(midScan.truncated && midScan.nodes.first?.childDirectoryCount == nil)
        }
    }

    @Test func malformedRootPathsAreRejectedWithoutScanningAnAlternatePath() throws {
        try fixture { root in
            _ = try directory("real-child", in: root)
            let graph = DirectoryCrystal.scan(roots: [root.path + String(UnicodeScalar(0)!) + "suffix", "relative/path", root.path + "/../escape"])
            #expect(graph.nodes.isEmpty)
            #expect(graph.truncated)
            #expect(graph.issues.contains { $0.contains("Invalid root") })
        }
    }

    @Test func nativeRootSelectionScopesMetadataWithoutBroadNameBasedDenial() {
        #expect(DirectoryCrystal.requiresExplicitSelection("/Users/example/Documents"))
        #expect(DirectoryCrystal.requiresExplicitSelection("/Volumes/Work"))
        #expect(!DirectoryCrystal.requiresExplicitSelection("/Users/example/Code"))
        #expect(!DirectoryCrystal.requiresExplicitSelection("/Users/example/Documents", approvedRoots: ["/Users/example/Documents"]))
        #expect(!DirectoryCrystal.requiresExplicitSelection("/Volumes/Work/project", approvedRoots: ["/Volumes/Work"]))
        #expect(DirectoryCrystal.requiresExplicitSelection("/Volumes/Work-copy", approvedRoots: ["/Volumes/Work"]))
    }

    @Test func scansOnlyRealDirectoryBranchesAndImmediateCounts() throws {
        try fixture { root in
            let a = try directory("a/leaf", in: root)
            _ = try directory("b", in: root)
            for ignored in [".secret", ".git", ".build", ".swiftpm", ".worktrees", "node_modules", "target", "__pycache__"] {
                _ = try directory("\(ignored)/excluded", in: root)
            }
            FileManager.default.createFile(atPath: root.appendingPathComponent("plain.txt").path, contents: nil)
            let date = Date(timeIntervalSince1970: 42)
            let graph = DirectoryCrystal.scan(roots: [root.path], now: date)
            #expect(Set(graph.nodes.map(\.path)) == [root.path, root.path + "/a", a, root.path + "/b"])
            #expect(graph.nodes.first { $0.path == root.path }?.childDirectoryCount == 2)
            #expect(graph.nodes.first { $0.path == a }?.childDirectoryCount == 0)
            #expect(graph.scannedAt == date)
            #expect(!graph.issues.isEmpty)
            #expect(!graph.truncated)
            #expect(graph.branches.count == 3)
            for edge in graph.branches {
                #expect((edge.child as NSString).deletingLastPathComponent == edge.parent)
            }
        }
    }
}
