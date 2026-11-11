import CoreGraphics
import Foundation
import FleetCore
import Testing
@testable import FleetConsoleApp

struct AwarenessGraphTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ id: String = "agent", pid: Int32 = 42, project: String? = "/work/api") -> AgentSession {
        AgentSession(id: id, tool: "Codex", pid: pid, project: project,
                     startedAt: now.addingTimeInterval(-60), cpuPct: 99, memMB: 999,
                     commandLine: "codex --resume \(id)")
    }

    private func process(_ pid: Int32 = 42, parent: Int32 = 1, command: String = "codex --resume agent",
                         cpu: Double = 3, bytes: Int64 = 64 * 1_048_576,
                         startedAt: Date? = nil) -> ProcessRow {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return ProcessRow(id: pid, pid: pid, ppid: parent, pgid: pid, uid: 501, user: "test",
                          name: "process-\(pid)", commandLine: command, cpuPercent: cpu,
                          residentBytes: bytes, ports: [],
                          startSignature: formatter.string(from: startedAt ?? now.addingTimeInterval(-60)),
                          stateField: "R")
    }

    @Test(arguments: ["match", "within-second", "pid-reused", "other-command", "whitespace-command", "missing-start", "invalid-signature", "missing-signature"])
    func sessionProcessLinkRequiresCompleteExactIdentity(_ scenario: String) throws {
        var agent = session()
        var row = process()
        switch scenario {
        case "within-second": agent.startedAt = agent.startedAt?.addingTimeInterval(0.9)
        case "pid-reused": row.startSignature = process(startedAt: now).startSignature
        case "other-command": row.commandLine += " --different"
        case "whitespace-command": agent.commandLine = " "; row.commandLine = " "
        case "missing-start": agent.startedAt = nil
        case "invalid-signature": row.startSignature = "not a timestamp"
        case "missing-signature": row.startSignature = ""
        default: break
        }
        let graph = AwarenessGraph.build(sessions: [agent], processes: [row], processCapturedAt: now,
                                         topology: nil, now: now)
        let node = try #require(graph.nodes.first { $0.sessionID == agent.id })
        let links = graph.edges.filter { $0.source == node.id }
        let matched = scenario == "match" || scenario == "within-second"
        #expect(links.count == (matched ? 1 : 0))
        #expect(node.cpuPercent == (matched ? 3 : nil))
        #expect(node.memoryMB == (matched ? 64 : nil))
        if matched {
            let edge = try #require(links.first)
            #expect(edge.evidence.contains("command"))
            #expect(edge.evidence.contains("start"))
            #expect(graph.nodes.contains { $0.id == edge.target && $0.kind == .process && $0.pid == 42 })
            #expect(node.subtitle.localizedCaseInsensitiveContains("current"))
        }
    }

    @Test(arguments: ["fresh", "stale", "unavailable", "future"])
    func processParentageAndMetricsRequireOneFreshSnapshot(_ scenario: String) throws {
        let capture: Date? = switch scenario {
        case "stale": now.addingTimeInterval(-60)
        case "unavailable": nil
        case "future": now.addingTimeInterval(60)
        default: now
        }
        let graph = AwarenessGraph.build(sessions: [session()],
                                         processes: [process(), process(43, parent: 42, command: "swift test")],
                                         processCapturedAt: capture, topology: nil, now: now)
        let agent = try #require(graph.nodes.first { $0.kind == .session })
        let root = try #require(graph.nodes.first { $0.kind == .process && $0.pid == 42 })
        let child = try #require(graph.nodes.first { $0.kind == .process && $0.pid == 43 })
        let parentage = graph.edges.filter { $0.source == root.id && $0.target == child.id }
        #expect(parentage.count == (scenario == "fresh" ? 1 : 0))
        #expect(graph.observedAt == capture)
        if scenario == "fresh" {
            #expect(parentage.first?.evidence.contains("PPID") == true)
            #expect(agent.cpuPercent == 3)
            #expect(child.cpuPercent == 3)
        } else {
            #expect(agent.cpuPercent == nil)
            #expect(root.cpuPercent == nil)
            #expect(child.memoryMB == nil)
            #expect(!graph.edges.contains { $0.source == agent.id })
            let expected = scenario == "stale" ? "stale" : "unavailable"
            #expect(agent.subtitle.localizedCaseInsensitiveContains(expected))
            #expect(root.subtitle.localizedCaseInsensitiveContains(expected))
        }
    }

    @Test(arguments: [0.0, 60.0])
    func registryEvidenceRemainsASeparateProvenanceForest(_ age: Double) throws {
        var record = ServiceRecord(id: "svc", friendlyName: "API", ownerAgent: "Codex", purpose: "Serve project",
                                   command: ["codex", "--resume", "agent"], cwd: "/work/api", pid: 42, pgid: 42,
                                   declaredPorts: [9000], leaseExpiresAt: now.addingTimeInterval(600), leaseTTLSec: 600,
                                   state: .running,
                                   evidence: Evidence(processExists: true, listeningPorts: [8080], portScanRan: true, checkedAt: now),
                                   resources: ResourceSample(cpuPct: 2, memMB: 16, sampledAt: now), updatedAt: now)
        record.claimed = true
        let snapshot = Snapshot(generatedAt: now, daemon: DaemonInfo(version: "test", pid: 1, startedAt: now),
                                services: [record], sessions: [session("topology-only")])
        let topology = FleetTopology(snapshot: snapshot, now: now)
        let graph = AwarenessGraph.build(sessions: [session()], processes: [process()], processCapturedAt: now,
                                         topology: topology, now: now.addingTimeInterval(age))
        var permuted = topology
        permuted.nodes.reverse()
        permuted.edges.reverse()
        let reordered = AwarenessGraph.build(sessions: [session()], processes: [process()], processCapturedAt: now,
                                             topology: permuted, now: now.addingTimeInterval(age))
        #expect(graph.nodes == reordered.nodes)
        #expect(graph.edges == reordered.edges)
        #expect(graph.bounds == reordered.bounds)
        #expect(graph.nodes.allSatisfy { graph.bounds.contains(frame($0)) })
        let owner = try #require(graph.nodes.first { $0.kind == .owner })
        let service = try #require(graph.nodes.first { $0.kind == .service })
        let agent = try #require(graph.nodes.first { $0.kind == .session })
        #expect(service.serviceID == "svc")
        #expect(service.subtitle.contains("visibility only"))
        #expect(graph.nodes.filter { $0.kind == .session }.count == 1)
        #expect(!graph.edges.contains { $0.source == owner.id && $0.target == agent.id })
        #expect(!graph.edges.contains { $0.source == agent.id && $0.target == service.id })
        let registryIDs = Set(graph.nodes.filter { $0.id.hasPrefix("registry:") }.map(\.id))
        #expect(!graph.edges.contains { registryIDs.contains($0.source) != registryIDs.contains($0.target) })
        #expect(graph.edges.contains { $0.source == owner.id && $0.target == service.id && $0.evidence == "fleetd service registry" })
        if age == 0 {
            #expect(service.cpuPercent == 2)
            #expect(graph.edges.contains { $0.evidence == "fleetd process identity check" })
            #expect(graph.edges.contains { $0.evidence == "fleetd group listener scan" })
            #expect(graph.nodes.contains { $0.kind == .listener && $0.title == ":8080" })
            #expect(!graph.nodes.contains { $0.title == ":9000" })
        } else {
            #expect(service.cpuPercent == nil)
            #expect(service.subtitle.localizedCaseInsensitiveContains("stale"))
            #expect(!graph.edges.contains { $0.evidence == "fleetd process identity check" || $0.evidence == "fleetd group listener scan" })
        }
    }

    @Test func largeInventoryBoundsDescendantsAndBalancesUnassociatedContext() {
        let descendants = (100..<2100).map { process(Int32($0), parent: 42, command: "swift worker", cpu: 1, bytes: 1) }
        let unrelated = (3000..<5000).map { process(Int32($0), command: "other", cpu: 1, bytes: 1) }
        let rows = [process()] + descendants + unrelated +
            [process(9000, command: "cpu-heavy", cpu: 900, bytes: 1),
             process(9001, command: "memory-heavy", cpu: 0, bytes: 20_000 * 1_048_576)]
        let graph = AwarenessGraph.build(sessions: [session()], processes: rows, processCapturedAt: now,
                                         topology: nil, now: now)
        let processes = graph.nodes.filter { $0.kind == .process }
        #expect(graph.nodes.count <= 120)
        #expect(processes.count <= 21) // one verified root, twelve descendants, eight context rows
        #expect(graph.nodes.contains { $0.pid == 9000 })
        #expect(graph.nodes.contains { $0.pid == 9001 })
        #expect(graph.omittedProcesses == rows.count - processes.count)
        let unassociated = processes.filter { $0.pid != 42 && !descendants.map(\.pid).contains($0.pid ?? -1) }
        #expect(unassociated.count == 8)
        let ids = Set(graph.nodes.map(\.id))
        #expect(graph.edges.allSatisfy { ids.contains($0.source) && ids.contains($0.target) })
    }

    @Test(arguments: [-1, 0, 1, 7, 120, 500])
    func totalLimitIsHardCappedAndSessionsWinOverSecondaryNodes(_ limit: Int) {
        let agents = (0..<160).map { session("session-\($0)", pid: Int32($0 + 100), project: "/work/\($0)") }
        let graph = AwarenessGraph.build(sessions: agents, processes: [process()], processCapturedAt: now,
                                         topology: nil, now: now, limit: limit)
        let cap = min(120, max(0, limit))
        #expect(graph.nodes.count == cap)
        #expect(graph.nodes.allSatisfy { $0.kind == .session })
        #expect(graph.edges.isEmpty)
        #expect(graph.omittedProcesses == 1)
    }

    private func frame(_ node: AwarenessGraph.Node) -> CGRect {
        CGRect(x: node.position.x - node.size.width / 2, y: node.position.y - node.size.height / 2,
               width: node.size.width, height: node.size.height)
    }

    @Test(arguments: [1, 4, 40])
    func layoutIsOrganicNonoverlappingAndMetricIndependent(_ projectCount: Int) throws {
        let agents = (0..<(projectCount * 3)).map {
            session("agent-\($0)", pid: Int32(100 + $0), project: "/work/project-\($0 / 3)")
        }
        let rows = agents.flatMap { agent in
            [process(agent.pid, command: agent.commandLine),
             process(agent.pid + 1000, parent: agent.pid, command: "swift test")]
        }
        let first = AwarenessGraph.build(sessions: agents, processes: rows, processCapturedAt: now, topology: nil, now: now)
        let reversed = AwarenessGraph.build(sessions: agents.reversed(), processes: rows.reversed(),
                                            processCapturedAt: now, topology: nil, now: now)
        #expect(first.nodes == reversed.nodes)
        #expect(first.edges == reversed.edges)
        #expect(first.bounds == reversed.bounds)
        var updated = rows
        for index in updated.indices {
            updated[index].cpuPercent = Double(index * 7)
            updated[index].residentBytes = Int64(index * 1_048_576)
        }
        let next = AwarenessGraph.build(sessions: agents, processes: updated, processCapturedAt: now.addingTimeInterval(1),
                                        topology: nil, now: now.addingTimeInterval(1))
        let positions = Dictionary(uniqueKeysWithValues: first.nodes.map { ($0.id, $0.position) })
        #expect(next.nodes.allSatisfy { positions[$0.id] == $0.position })
        #expect(first.nodes.allSatisfy { first.bounds.contains(frame($0)) })
        let frames = first.nodes.map(frame)
        let overlaps = frames.indices.contains { index in
            frames.indices.contains { $0 > index && frames[index].intersects(frames[$0]) }
        }
        #expect(!overlaps)
        #expect(Set(first.nodes.map { $0.position.x }).count > 2)
        #expect(Set(first.nodes.map { $0.position.y }).count > 2)
        for project in first.nodes.filter({ $0.kind == .project }) {
            let members = first.nodes.filter { $0.kind == .session && $0.projectPath == project.projectPath }
            #expect(members.allSatisfy { hypot($0.position.x - project.position.x, $0.position.y - project.position.y) < 800 })
        }
    }

    @Test func emptyObservationsUseOnlyAnHonestCentralMachineFallback() throws {
        let graph = AwarenessGraph.build(sessions: [], processes: [], processCapturedAt: nil, topology: nil, now: now)
        let machine = try #require(graph.nodes.first)
        #expect(graph.nodes.count == 1)
        #expect(machine.kind == .machine)
        #expect(machine.position == .zero)
        #expect(machine.cpuPercent == nil)
        #expect(machine.memoryMB == nil)
        #expect(machine.subtitle.localizedCaseInsensitiveContains("unavailable"))
        #expect(graph.bounds.contains(frame(machine)))
        #expect(graph.edges.isEmpty)
        #expect(graph.observedAt == nil)
        let processOnly = AwarenessGraph.build(sessions: [], processes: [process()], processCapturedAt: now, topology: nil, now: now)
        #expect(!processOnly.nodes.contains { $0.kind == .machine || $0.kind == .project || $0.kind == .session })
    }

    @Test func explicitProjectsAndActualSessionTranscriptArePrimary() throws {
        var agent = session()
        agent.sessionName = "Investigate timeout"
        agent.preview = "Running the timeout regression test"
        agent.previewTurn = .assistant
        let other = session("other", pid: 43, project: "/elsewhere/api")
        let unknown = session("unknown", pid: 44, project: nil)
        let graph = AwarenessGraph.build(sessions: [unknown, other, agent], processes: [],
                                         processCapturedAt: nil, topology: nil, now: now)
        let node = try #require(graph.nodes.first { $0.sessionID == agent.id })
        #expect(node.kind == .session)
        #expect(node.title.contains("Codex"))
        #expect(node.title.contains("Investigate timeout"))
        #expect(node.activity == agent.preview)
        #expect(node.projectPath == "/work/api")
        #expect(node.subtitle.contains("api"))
        #expect(node.size == CGSize(width: 236, height: 136))
        #expect(node.cpuPercent == nil)
        let projects = graph.nodes.filter { $0.kind == .project }
        #expect(Set(projects.compactMap(\.projectPath)) == ["/work/api", "/elsewhere/api"])
        #expect(Set(projects.map(\.id)).count == 2)
        #expect(graph.edges.count == 2)
        #expect(graph.edges.allSatisfy { edge in
            projects.contains { $0.id == edge.source } && graph.nodes.contains { $0.id == edge.target && $0.kind == .session }
        })
        let unlinked = try #require(graph.nodes.first { $0.sessionID == "unknown" })
        #expect(!graph.edges.contains { $0.target == unlinked.id || $0.source == unlinked.id })
        #expect(!graph.nodes.contains { $0.kind == .machine })
    }
}
