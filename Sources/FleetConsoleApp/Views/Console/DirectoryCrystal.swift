import Foundation
import Darwin

/// A bounded metadata observation, not a dependency graph. Every branch is an
/// observed immediate directory relationship; exclusions are reported separately.
struct DirectoryCrystal: Equatable, Sendable {
    struct Node: Identifiable, Equatable, Sendable {
        var id: String { path }
        let path: String
        let parentPath: String?
        let rootPath: String
        let name: String
        let depth: Int
        let childDirectoryCount: Int?
        let unreadable: Bool
        let truncated: Bool
        let isSymbolicLink: Bool
        let position: CGPoint
    }
    struct Branch: Identifiable, Equatable, Sendable {
        let parent: String
        let child: String
        var id: String { "\(parent.utf8.count):\(parent)\(child)" }
    }
    let roots: [String]
    let nodes: [Node]
    let branches: [Branch]
    let bounds: CGRect
    let scannedAt: Date
    let truncated: Bool
    let issues: [String]

    /// Automatic workspace discovery avoids privacy prompts. A folder chosen
    /// through the native picker is an explicit metadata scope, not an OS grant.
    static func requiresExplicitSelection(_ path: String, approvedRoots: Set<String> = []) -> Bool {
        if approvedRoots.contains(where: { path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/") }) { return false }
        let parts = path.split(separator: "/")
        if parts.first == "Volumes" { return true }
        let privateNames: Set<String> = ["Desktop", "Documents", "Downloads", "Pictures", "Music", "Movies", "Library"]
        return parts.count >= 3 && parts[0] == "Users" && privateNames.contains(String(parts[2]))
    }

    static func scan(roots: [String], expanded: Set<String> = [], requiredPaths: [String] = [],
                     explicitlySelectedRoots: Set<String> = [], maxNodes: Int = 600, maxDepth: Int = 3, now: Date = Date(),
                     isCancelled: () -> Bool = { false }) -> DirectoryCrystal {
        withoutActuallyEscaping(isCancelled) { cancellation in
            let scanner = Scanner(limit: min(600, max(0, maxNodes)), depth: max(0, min(32, maxDepth)),
                                  expanded: expanded, required: requiredPaths, approved: explicitlySelectedRoots, cancelled: cancellation)
            return scanner.run(roots: roots, now: now)
        }
    }

    private final class Scanner {
        struct Record {
            let path: String
            let parent: String?
            let root: String
            let depth: Int
            var count: Int?
            var unreadable = false
            var truncated = false
        }
        let limit: Int
        let depth: Int
        let expanded: Set<String>
        let required: [String]
        let approved: Set<String>
        let cancelled: () -> Bool
        var records: [String: Record] = [:]
        var observedChildren: [String: [String]] = [:]
        var issues: Set<String> = ["Coverage excludes hidden entries and generated caches: .git, .build, .swiftpm, .worktrees, node_modules, target, __pycache__. Symbolic links are never followed."]
        var visits = 0
        var stopped = false
        var incomplete = false
        static let ignored: Set<String> = [".git", ".build", ".swiftpm", ".worktrees", "node_modules", "target", "__pycache__"]

        init(limit: Int, depth: Int, expanded: Set<String>, required: [String], approved: Set<String>, cancelled: @escaping () -> Bool) {
            self.limit = limit
            self.depth = depth
            self.expanded = expanded
            self.required = required.sorted()
            self.approved = approved
            self.cancelled = cancelled
        }

        func stop() -> Bool {
            if stopped { return true }
            if cancelled() {
                issues.insert("Scan cancelled; coverage is partial.")
                incomplete = true
                stopped = true
            }
            return stopped
        }

        // Default discovery never requests private-folder/volume access. Native
        // picker selections define a read-only metadata scope; OS grants still apply.
        func protected(_ path: String) -> Bool {
            DirectoryCrystal.requiresExplicitSelection(path, approvedRoots: approved)
        }

        /// Walk every component relative to an open descriptor. O_NOFOLLOW also
        /// rejects symlink roots and symlink ancestors, including a swap race.
        func openRoot(_ path: String) -> (Bool, Int32) {
            var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard fd >= 0 else { return (false, -1) }
            let parts = path.split(separator: "/").map(String.init)
            if parts.isEmpty { return (true, fd) }
            for (index, part) in parts.enumerated() {
                var info = stat()
                guard fstatat(fd, part, &info, AT_SYMLINK_NOFOLLOW) == 0,
                      (info.st_mode & S_IFMT) == S_IFDIR else {
                    close(fd)
                    return (false, -1)
                }
                let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                close(fd)
                if next < 0 { return (index == parts.count - 1, -1) }
                fd = next
            }
            return (true, fd)
        }

        func run(roots input: [String], now: Date) -> DirectoryCrystal {
            // Do not resolve symlinks or silently reinterpret relative paths.
            func valid(_ path: String) -> Bool {
                path.hasPrefix("/") && !path.utf8.contains(0) && !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
            }
            if input.contains(where: { !valid($0) }) {
                issues.insert("Invalid root path omitted; choose an absolute directory without NUL or traversal components.")
                incomplete = true
            }
            let candidates = Set(input.filter(valid).map { $0 == "/" ? $0 : String($0.reversed().drop(while: { $0 == "/" }).reversed()) }).sorted()
            let outermost = candidates.filter { path in
                !candidates.contains { $0 != path && path.hasPrefix($0 == "/" ? "/" : $0 + "/") }
            }
            var roots: [String] = []
            // Finish all actual priority chains globally, then expansion windows,
            // before ordinary folders. Cached enumeration shares one entry budget.
            for phase in 0...2 {
                for path in outermost.sorted(by: prioritized) where priority(path) <= phase {
                    if stop() { break }
                    if protected(path) {
                        issues.insert("Privacy-protected directory omitted without requesting permission: \(path)")
                        incomplete = true
                        continue
                    }
                    let (exists, fd) = openRoot(path)
                    guard exists else {
                        issues.insert("Directory missing, inaccessible, or symbolic-link path omitted: \(path)")
                        incomplete = true
                        continue
                    }
                    if !roots.contains(path) { roots.append(path) }
                    if records[path] != nil || records.count < limit {
                        visit(path: path, parent: nil, root: path, level: 0, allowance: depth, fd: fd, phase: phase)
                    } else {
                        if fd >= 0 { close(fd) }
                        incomplete = true
                        issues.insert("Node budget reached (\(limit)); coverage is partial.")
                    }
                }
            }
            let sorted = records.values.sorted { $0.path < $1.path }
            let positions = layout(sorted)
            let nodes = sorted.map {
                Node(path: $0.path, parentPath: $0.parent, rootPath: $0.root,
                     name: ($0.path as NSString).lastPathComponent, depth: $0.depth,
                     childDirectoryCount: $0.count, unreadable: $0.unreadable,
                     truncated: $0.truncated, isSymbolicLink: false, position: positions[$0.path] ?? .zero)
            }
            let branches = sorted.compactMap { record in
                record.parent.map { Branch(parent: $0, child: record.path) }
            }
            return DirectoryCrystal(roots: roots.sorted(), nodes: nodes, branches: branches, bounds: rectangle(Array(positions.values)),
                                    scannedAt: now, truncated: incomplete, issues: issues.sorted())
        }

        func visit(path: String, parent: String?, root: String, level: Int, allowance: Int, fd: Int32, phase: Int) {
            defer { if fd >= 0 { close(fd) } }
            if records[path] == nil { records[path] = Record(path: path, parent: parent, root: root, depth: level) }
            guard fd >= 0 else {
                records[path]?.unreadable = true
                records[path]?.truncated = true
                incomplete = true
                issues.insert("Unreadable directory: \(path)")
                return
            }
            var children: [String]
            if let cached = observedChildren[path] {
                children = cached
            } else {
                let duplicate = stop() ? -1 : dup(fd)
                guard duplicate >= 0, let stream = fdopendir(duplicate) else {
                    if duplicate >= 0 { close(duplicate) }
                    records[path]?.truncated = true
                    incomplete = true
                    if !stopped { records[path]?.unreadable = true; issues.insert("Unreadable directory: \(path)") }
                    return
                }
                defer { closedir(stream) }
                children = []
                var partial = false
                while true {
                    if stop() { partial = true; break }
                    if visits >= 12_000 {
                        partial = true
                        incomplete = true
                        issues.insert("Entry budget reached (12000); directory counts are partial.")
                        break
                    }
                    errno = 0
                    guard let entry = readdir(stream) else {
                        if errno != 0 { partial = true; records[path]?.unreadable = true; issues.insert("Directory enumeration failed: \(path)") }
                        break
                    }
                    visits += 1
                    let name = withUnsafePointer(to: entry.pointee.d_name) {
                        $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
                    }
                    if name.hasPrefix(".") || Self.ignored.contains(name) { continue }
                    var info = stat()
                    guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                        partial = true
                        issues.insert("Metadata unavailable: \(path)/\(name)")
                        continue
                    }
                    if (info.st_mode & S_IFMT) == S_IFDIR, info.st_flags & UInt32(UF_HIDDEN) == 0 { children.append(name) }
                }
                records[path]?.count = partial ? nil : children.count
                records[path]?.truncated = partial
                if partial { incomplete = true }
                observedChildren[path] = children
            }
            let allowed = expanded.contains(path) ? max(allowance, level + 2) : allowance
            for name in children.sorted(by: { prioritized(path == "/" ? "/" + $0 : path + "/" + $0,
                                                        path == "/" ? "/" + $1 : path + "/" + $1) }) {
                let child = path == "/" ? "/" + name : path + "/" + name
                if priority(child) > phase { continue }
                let requiredAncestor = required.contains { $0 == child || $0.hasPrefix(child + "/") }
                let expandedAncestor = expanded.contains { $0 == child || $0.hasPrefix(child + "/") }
                if stop() || (records[child] == nil && records.count >= limit) || (level >= allowed && !requiredAncestor && !expandedAncestor) {
                    records[path]?.truncated = true
                    incomplete = true
                    issues.insert(level >= allowed ? "Depth limit reached: \(path)" : "Node budget or cancellation limited coverage: \(path)")
                    continue
                }
                if protected(child) {
                    records[path]?.truncated = true
                    incomplete = true
                    issues.insert("Privacy-protected directory omitted without requesting permission: \(child)")
                    continue
                }
                let childFD = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                // Revalidate against a concurrent replacement before admitting it.
                var info = stat()
                guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
                    if childFD >= 0 { close(childFD) }
                    records[path]?.truncated = true
                    incomplete = true
                    continue
                }
                visit(path: child, parent: path, root: root, level: level + 1, allowance: allowed, fd: childFD, phase: phase)
            }
        }

        func priority(_ path: String) -> Int {
            if required.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) { return 0 }
            if expanded.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) { return 0 }
            if expanded.contains(where: { path.hasPrefix($0 + "/") && path.dropFirst($0.count + 1).split(separator: "/").count <= 2 }) { return 1 }
            return 2
        }

        func prioritized(_ lhs: String, _ rhs: String) -> Bool {
            let left = priority(lhs), right = priority(rhs)
            return left == right ? lhs < rhs : left < right
        }

        struct Cell: Hashable {
            let q: Int
            let r: Int
            var point: CGPoint { CGPoint(x: Double(q) * 80 + Double(r) * 40, y: Double(r) * 69.2820323027551) }
        }

        func seed(_ path: String) -> Int {
            // Swift's randomized Hasher must not affect persistent geometry.
            var hash: UInt64 = 14695981039346656037
            for byte in path.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
            return Int(hash % 6)
        }

        func rectangle(_ points: [CGPoint]) -> CGRect {
            guard let first = points.first else { return .zero }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for point in points {
                minX = min(minX, point.x); maxX = max(maxX, point.x)
                minY = min(minY, point.y); maxY = max(maxY, point.y)
            }
            return CGRect(x: minX - 40, y: minY - 40, width: maxX - minX + 80, height: maxY - minY + 80)
        }

        func layout(_ records: [Record]) -> [String: CGPoint] {
            let axes = [Cell(q: 1, r: 0), Cell(q: 0, r: 1), Cell(q: -1, r: 1),
                        Cell(q: -1, r: 0), Cell(q: 0, r: -1), Cell(q: 1, r: -1)]
            let fan = [0, 1, 5, 2, 4, 3]
            let children = Dictionary(grouping: records.filter { $0.parent != nil }, by: { $0.parent! })
            var positions: [String: CGPoint] = [:]
            var occupiedRootBounds: [CGRect] = []
            for root in records.filter({ $0.parent == nil }) {
                var local: [String: Cell] = [root.path: Cell(q: 0, r: 0)]
                var occupied: Set<Cell> = [Cell(q: 0, r: 0)]
                var queue = [root.path]
                var cursor = 0
                while cursor < queue.count {
                    let parent = queue[cursor]; cursor += 1
                    let siblings = (children[parent] ?? []).sorted { $0.path < $1.path }
                    let origin = local[parent]!
                    for (index, child) in siblings.enumerated() {
                        let axis = axes[(seed(parent) + fan[index % 6]) % 6]
                        var radius = 2 + siblings.count / 6 + index / 6
                        var cell = Cell(q: origin.q + axis.q * radius, r: origin.r + axis.r * radius)
                        while occupied.contains(cell) {
                            radius += 1
                            cell = Cell(q: origin.q + axis.q * radius, r: origin.r + axis.r * radius)
                        }
                        local[child.path] = cell; occupied.insert(cell); queue.append(child.path)
                    }
                }
                let box = rectangle(local.values.map(\.point))
                var offset = CGPoint.zero
                var ring = 0
                while occupiedRootBounds.contains(where: { $0.intersects(box.offsetBy(dx: offset.x, dy: offset.y).insetBy(dx: -120, dy: -120)) }) {
                    ring += 1
                    let axis = axes[seed(root.path)]
                    let stride = max(box.width, box.height) + 320
                    offset = CGPoint(x: axis.point.x / 80 * stride * Double(ring),
                                     y: axis.point.y / 80 * stride * Double(ring))
                }
                occupiedRootBounds.append(box.offsetBy(dx: offset.x, dy: offset.y))
                for (path, cell) in local {
                    positions[path] = CGPoint(x: cell.point.x + offset.x, y: cell.point.y + offset.y)
                }
            }
            return positions
        }

    }
}
