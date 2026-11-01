import CoreGraphics
import Foundation
import FleetCore

/// Observational projection only. Detected sessions and registry ownership have
/// independent provenance; proximity on the canvas never establishes ownership.
struct AwarenessGraph {
    enum Kind: Equatable { case machine, project, session, owner, service, process, listener }

    struct Node: Identifiable, Equatable {
        var id: String
        var kind: Kind
        var title: String
        var subtitle: String
        var activity: String?
        var pid: Int32?
        var sessionID: String?
        var serviceID: String?
        var projectPath: String?
        var symbol: String
        var cpuPercent: Double?
        var memoryMB: Double?
        /// Card center in world coordinates, not its top-left corner.
        var position: CGPoint
        var size: CGSize
    }

    struct Edge: Identifiable, Equatable {
        var source: String
        var target: String
        var label: String
        var evidence: String
        var id: String { [source, target, label, evidence].map { "\($0.utf8.count):\($0)" }.joined() }
    }

    let nodes: [Node]
    let edges: [Edge]
    let bounds: CGRect
    let omittedProcesses: Int
    let observedAt: Date?

    static func build(sessions: [AgentSession], processes: [ProcessRow], processCapturedAt: Date?,
                      topology: FleetTopology?, now: Date = Date(), limit: Int = 120) -> AwarenessGraph {
        var nodes: [Node] = []
        var edges: [Edge] = []
        var projects = Set<String>()
        var displayedProcesses = Set<Int32>()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        formatter.isLenient = false
        let fresh = processCapturedAt.map { (0...15).contains(now.timeIntervalSince($0)) } == true
        let observation = fresh ? "current process observation" :
            (processCapturedAt.map { now.timeIntervalSince($0) > 15 } == true ? "last observed · process snapshot stale" : "process observation unavailable")
        let processByPID = Dictionary(grouping: processes, by: \.pid).compactMapValues { rows in
            rows.count == 1 ? rows.first : nil
        }
        for session in sessions.sorted(by: { $0.id < $1.id }) {
            let sessionID = "session:" + session.id
            let project = session.project.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            let candidate = processByPID[session.pid]
            let matched: ProcessRow? = candidate.flatMap { row in
                guard fresh, !session.commandLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      session.commandLine == row.commandLine, let startedAt = session.startedAt,
                      let processStart = formatter.date(from: row.startSignature),
                      abs(processStart.timeIntervalSince(startedAt)) <= 1 else { return nil }
                return row
            }
            nodes.append(Node(id: sessionID, kind: .session,
                              title: [session.tool, session.sessionName].compactMap { $0 }.joined(separator: " · "),
                              subtitle: (project.map { ($0 as NSString).lastPathComponent + " · " } ?? "") +
                                  "PID \(session.pid) · " + (matched != nil ? observation : (fresh ? "process identity unverified" : observation)),
                              activity: session.preview, pid: session.pid, sessionID: session.id,
                              projectPath: project, symbol: session.symbol,
                              cpuPercent: matched.flatMap { $0.cpuPercent.isFinite && $0.cpuPercent >= 0 ? $0.cpuPercent : nil },
                              memoryMB: matched.flatMap { $0.residentBytes >= 0 ? Double($0.residentBytes) / 1_048_576 : nil },
                              position: .zero, size: CGSize(width: 236, height: 136)))
            if let row = matched {
                let processID = Self.processID(row)
                if displayedProcesses.insert(row.pid).inserted {
                    nodes.append(processNode(row, fresh: fresh, observation: observation))
                }
                edges.append(Edge(source: sessionID, target: processID, label: "verified process",
                                  evidence: "Detected session and current process observation agree on PID, exact nonempty command and start time within 1 second"))
            }
            if let project {
                let projectID = "project:" + project
                if projects.insert(project).inserted {
                    nodes.append(Node(id: projectID, kind: .project, title: (project as NSString).lastPathComponent,
                                      subtitle: project, projectPath: project, symbol: "folder",
                                      position: .zero, size: CGSize(width: 150, height: 80)))
                }
                edges.append(Edge(source: projectID, target: sessionID, label: "working directory",
                                  evidence: "Detected session explicitly reports project: \(project)"))
            }
        }
        let rows = processByPID.values.sorted { $0.pid < $1.pid }
        var associated = displayedProcesses
        if fresh {
            let children = Dictionary(grouping: rows, by: \.ppid)
            var queue = displayedProcesses.sorted().map { (root: $0, pid: $0) }
            var counts: [Int32: Int] = [:]
            var descendants = 0
            var index = 0
            while index < queue.count {
                let parent = queue[index]
                index += 1
                for child in children[parent.pid] ?? [] where associated.insert(child.pid).inserted {
                    // Walk the actual closure so omitted descendants cannot be
                    // silently relabelled as unassociated high-load context.
                    queue.append((root: parent.root, pid: child.pid))
                    if counts[parent.root, default: 0] < 12 && descendants < 48 {
                        displayedProcesses.insert(child.pid)
                        nodes.append(processNode(child, fresh: fresh, observation: observation))
                        counts[parent.root, default: 0] += 1
                        descendants += 1
                    }
                }
            }
        }
        // A small context sample balances CPU and resident memory, not a table
        // of the entire inventory. These rows carry no inferred agent owner.
        let remaining = rows.filter { !associated.contains($0.pid) }
        let cpu = remaining.sorted {
            let a = validMetric($0.cpuPercent) ?? 0, b = validMetric($1.cpuPercent) ?? 0
            return a == b ? $0.pid < $1.pid : a > b
        }
        let memory = remaining.sorted { $0.residentBytes == $1.residentBytes ? $0.pid < $1.pid : $0.residentBytes > $1.residentBytes }
        var contextual = Set<Int32>()
        for index in 0..<min(8, remaining.count) {
            for list in [cpu, memory] where contextual.count < 8 {
                let row = list[index]
                if contextual.insert(row.pid).inserted {
                    displayedProcesses.insert(row.pid)
                    nodes.append(processNode(row, fresh: fresh, observation: observation))
                }
            }
        }
        if fresh {
            for row in rows where displayedProcesses.contains(row.pid) && row.pid != row.ppid {
                guard displayedProcesses.contains(row.ppid), let parent = processByPID[row.ppid] else { continue }
                edges.append(Edge(source: processID(parent), target: processID(row), label: "observed child",
                                  evidence: "PPID \(row.ppid) observed in the same current process snapshot"))
            }
        }
        if let topology {
            let registryFresh = !topology.isStale && topology.generatedAt <= now &&
                topology.validUntil.map { now <= $0 } == true
            for node in topology.nodes.sorted(by: { $0.id < $1.id }) {
                let kind: Kind
                let symbol: String
                let size: CGSize
                switch node.kind {
                case .owner: kind = .owner; symbol = "person.crop.circle"; size = CGSize(width: 150, height: 80)
                case .service: kind = .service; symbol = "gearshape.2"; size = CGSize(width: 210, height: 100)
                case .process: kind = .process; symbol = "terminal"; size = CGSize(width: 170, height: 60)
                case .listener: kind = .listener; symbol = "network"; size = CGSize(width: 130, height: 60)
                case .session: continue // Detected sessions come only from the actual session source.
                }
                if !registryFresh && (kind == .process || kind == .listener) { continue }
                nodes.append(Node(id: "registry:" + node.id, kind: kind, title: node.title,
                                  subtitle: node.detail + (registryFresh ? "" : " · registry observation stale or unavailable"),
                                  serviceID: node.serviceID, symbol: symbol,
                                  cpuPercent: registryFresh ? node.cpuPct.flatMap(validMetric) : nil,
                                  memoryMB: registryFresh ? node.memMB.flatMap(validMetric) : nil,
                                  position: .zero, size: size))
            }
            for edge in topology.edges {
                let label: String
                switch edge.kind {
                case .owns: label = "registry owner"
                case .verifiedLeader: guard registryFresh else { continue }; label = "verified leader"
                case .observedListener: guard registryFresh else { continue }; label = "observed listener"
                }
                edges.append(Edge(source: "registry:" + edge.source, target: "registry:" + edge.target,
                                  label: label, evidence: edge.provenance))
            }
        }
        let cap = min(120, max(0, limit))
        if nodes.isEmpty && cap > 0 {
            nodes.append(Node(id: "machine:local", kind: .machine, title: "This Mac",
                              subtitle: "Agent and process observations unavailable", symbol: "desktopcomputer",
                              position: .zero, size: CGSize(width: 180, height: 84)))
        }
        // Sessions get the budget first. Secondary detail never evicts an
        // observed agent; every edge is pruned to the selected endpoints.
        nodes = nodes.enumerated().sorted {
            let a = $0.element.kind == .session ? 0 : 1
            let b = $1.element.kind == .session ? 0 : 1
            return a == b ? $0.offset < $1.offset : a < b
        }.prefix(cap).map(\.element)
        let nodeIDs = Set(nodes.map(\.id))
        edges = edges.filter { nodeIDs.contains($0.source) && nodeIDs.contains($0.target) }
        let shown = Set(nodes.filter { !$0.id.hasPrefix("registry:") && $0.kind == .process }.compactMap(\.pid))
        let spatial = layout(nodes: nodes, edges: edges)
        return AwarenessGraph(nodes: spatial.nodes, edges: edges.sorted { $0.id < $1.id },
                              bounds: spatial.bounds, omittedProcesses: Set(processes.map(\.pid)).count - shown.count,
                              observedAt: processCapturedAt ?? topology?.generatedAt)
    }

    // MARK: - Stable world placement

    /// A finite identity-seeded packing pass, never a force simulation. Only
    /// identities, card geometry and observed relationships affect placement.
    private static func layout(nodes: [Node], edges: [Edge]) -> (nodes: [Node], bounds: CGRect) {
        guard !nodes.isEmpty else { return ([], .zero) }
        var index = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        func precedes(_ a: String, _ b: String) -> Bool {
            let ar = placementRank(index[a]!.kind), br = placementRank(index[b]!.kind)
            return ar == br ? a < b : ar < br
        }
        var parent: [String: String] = [:]
        for edge in edges.sorted(by: {
            let ar = placementRank(index[$0.source]!.kind), br = placementRank(index[$1.source]!.kind)
            return ar == br ? $0.id < $1.id : ar < br
        }) where parent[edge.target] == nil && edge.source != edge.target {
            parent[edge.target] = edge.source
        }
        let children = Dictionary(grouping: parent.keys, by: { parent[$0]! }).mapValues { $0.sorted(by: precedes) }
        let ordered = index.keys.sorted(by: precedes)
        let roots = ordered.filter { parent[$0] == nil }
        var placed = Set<String>()
        var occupied: [CGRect] = []
        var bounds = CGRect.null
        // Place primary project/session geometry before optional process context,
        // so a changing high-load sample cannot displace the agent clusters.
        // A missing root in cyclic input gets a deterministic independent anchor.
        var queue = roots
        while placed.count < index.count {
            if queue.isEmpty, let next = ordered.first(where: { !placed.contains($0) }) { queue.append(next) }
            queue.sort(by: precedes)
            let id = queue.removeFirst()
            guard placed.insert(id).inserted, var node = index[id] else { continue }
            let seed = stableHash(id)
            let angle = Double(seed % 65_536) * 2 * Double.pi / 65_536
            let preferred: CGPoint
            if let parentID = parent[id], placed.contains(parentID), let anchor = index[parentID] {
                let radius = max(anchor.size.width, node.size.width) * 0.9 + 80
                preferred = CGPoint(x: anchor.position.x + cos(angle) * radius,
                                    y: anchor.position.y + sin(angle) * radius)
            } else if node.kind == .machine {
                preferred = .zero
            } else {
                let radius = CGFloat(320 + (seed >> 16) % 700)
                preferred = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            }
            node.position = freePosition(near: preferred, size: node.size, seed: seed, occupied: occupied)
            index[id] = node
            let rect = frame(node.position, node.size)
            occupied.append(rect)
            bounds = bounds.union(rect)
            queue.append(contentsOf: children[id] ?? [])
        }
        return (index.values.sorted { $0.id < $1.id }, bounds.insetBy(dx: -64, dy: -64))
    }

    private static func placementRank(_ kind: Kind) -> Int {
        switch kind {
        case .machine, .project: 0
        case .session: 1
        case .owner: 2
        case .service: 3
        case .process: 4
        case .listener: 5
        }
    }

    private static func frame(_ center: CGPoint, _ size: CGSize) -> CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    private static func freePosition(near preferred: CGPoint, size: CGSize, seed: UInt64, occupied: [CGRect]) -> CGPoint {
        let phase = Double(seed % 1_024) * 2 * Double.pi / 1_024
        for step in 0..<1_024 {
            let radius = 44 * sqrt(Double(step))
            let angle = phase + Double(step) * 2.399963229728653
            let candidate = CGPoint(x: preferred.x + cos(angle) * radius, y: preferred.y + sin(angle) * radius)
            let rect = frame(candidate, size).insetBy(dx: -18, dy: -18)
            if !occupied.contains(where: { $0.intersects(rect) }) { return candidate }
        }
        // Guaranteed non-overlap even for adversarial hash collisions; bounded
        // search and at most 120 cards keep this off the normal path.
        return CGPoint(x: (occupied.map(\.maxX).max() ?? preferred.x) + size.width / 2 + 36, y: preferred.y)
    }

    /// Unlike Swift.Hasher this is deliberately stable across launches.
    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    private static func validMetric(_ value: Double) -> Double? {
        value.isFinite && value >= 0 ? value : nil
    }

    private static func processID(_ row: ProcessRow) -> String {
        "process:\(row.pid):\(row.startSignature)"
    }

    private static func processNode(_ row: ProcessRow, fresh: Bool, observation: String) -> Node {
        Node(id: processID(row), kind: .process, title: row.displayName,
             subtitle: "PID \(row.pid) · \(observation)", pid: row.pid, symbol: "terminal",
             cpuPercent: fresh ? validMetric(row.cpuPercent) : nil,
             memoryMB: fresh && row.residentBytes >= 0 ? Double(row.residentBytes) / 1_048_576 : nil,
             position: .zero, size: CGSize(width: 170, height: 60))
    }
}
