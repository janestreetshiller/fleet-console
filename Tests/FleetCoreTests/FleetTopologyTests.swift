import Foundation
import Testing
@testable import FleetCore

struct FleetTopologyTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func service(_ id: String = "svc", owner: String = "ouros") -> ServiceRecord {
        ServiceRecord(id: id, friendlyName: "API", ownerAgent: owner, purpose: "Serve project",
                      command: ["api"], cwd: "/project", pid: 42, pgid: 42,
                      declaredPorts: [9000], leaseExpiresAt: now.addingTimeInterval(600), leaseTTLSec: 600,
                      state: .running,
                      evidence: Evidence(processExists: true, listeningPorts: [8080], portScanRan: true, checkedAt: now),
                      resources: ResourceSample(cpuPct: 0, memMB: 64, sampledAt: now), updatedAt: now)
    }
    func snapshot(_ services: [ServiceRecord], sessions: [AgentSession] = [], messages: [AgentMessage] = []) -> Snapshot {
        Snapshot(generatedAt: now, daemon: DaemonInfo(version: "test", pid: 1, startedAt: now),
                 services: services, messages: messages, sessions: sessions)
    }

    @Test func observedEdgesAndMissingHealth() {
        let graph = FleetTopology(snapshot: snapshot([service()]), now: now)
        #expect(graph.edges.map(\.kind) == [.owns, .verifiedLeader, .observedListener])
        #expect(graph.nodes.filter { $0.kind == .listener }.map(\.title) == [":8080"])
        #expect(!graph.nodes.contains { $0.title == ":9000" })
        #expect(graph.nodes.first { $0.kind == .service }?.detail.contains("no health check configured") == true)
        #expect(graph.nodes.first { $0.kind == .service }?.cpuPct == 0)
    }

    @Test func staleAndMissingEvidenceNeverCreatesEdgesOrZeroSamples() {
        var record = service()
        record.evidence.checkedAt = nil
        record.resources = ResourceSample()
        let graph = FleetTopology(snapshot: snapshot([record]), now: now)
        #expect(graph.edges.count == 1)
        #expect(graph.nodes.first { $0.kind == .service }?.cpuPct == nil)
        #expect(graph.nodes.first { $0.kind == .service }?.memMB == nil)
        let stale = FleetTopology(snapshot: snapshot([service()]), now: now.addingTimeInterval(31))
        #expect(stale.isStale)
        #expect(stale.edges.map(\.kind) == [.owns])
        #expect(stale.nodes.first { $0.kind == .service }?.cpuPct == nil)
    }

    @Test func noSessionOwnerGuessingAndExactOwnerFilter() {
        let session = AgentSession(id: "session", tool: "ouros", pid: 42)
        let value = snapshot([service(), service("other", owner: "ouros-worker")], sessions: [session],
                             messages: [AgentMessage(agent: "mail-only", body: "question", needsReply: true)])
        let graph = FleetTopology(snapshot: value, now: now)
        let sessionID = "session:session"
        #expect(graph.nodes.contains { $0.id == sessionID })
        #expect(!graph.edges.contains { $0.source == sessionID || $0.target == sessionID })
        #expect(graph.nodes.contains { $0.kind == .owner && $0.title == "mail-only" })
        let filtered = FleetTopology(snapshot: value, owner: "ouros", now: now)
        #expect(filtered.nodes.filter { $0.kind == .owner }.map(\.title) == ["ouros"])
        #expect(!filtered.nodes.contains { $0.kind == .session })
    }

    @Test func claimedProcessAndUnverifiedGroupCannotAcquireAuthority() {
        var record = service()
        record.claimed = true
        record.pid = 43
        let graph = FleetTopology(snapshot: snapshot([record]), now: now)
        #expect(graph.nodes.first { $0.kind == .service }?.detail.contains("visibility only") == true)
        #expect(!graph.edges.contains { $0.kind == .verifiedLeader })
    }

    @Test func deterministicOrderAndRoundTrip() throws {
        let a = service("a"), b = service("b")
        let first = FleetTopology(snapshot: snapshot([a, b]), now: now)
        let second = FleetTopology(snapshot: snapshot([b, a]), now: now)
        #expect(first == second)
        #expect(try Codec.decode(FleetTopology.self, from: Codec.encode(first)) == first)
    }

    @Test func terminalRecordsAndFailedScansDoNotLeakListeners() {
        var terminal = service("old")
        terminal.state = .stopped
        var unscanned = service("new")
        unscanned.evidence.portScanRan = false
        unscanned.evidence.processExists = false
        let graph = FleetTopology(snapshot: snapshot([terminal, unscanned]), now: now)
        #expect(graph.nodes.filter { $0.kind == .service }.count == 1)
        #expect(graph.edges.map(\.kind) == [.owns])
    }
    @Test func invalidMetricsAndEvidenceExpiry() {
        var record = service()
        record.resources = ResourceSample(cpuPct: .infinity, memMB: -1, sampledAt: now)
        record.evidence.checkedAt = now.addingTimeInterval(-10)
        let graph = FleetTopology(snapshot: snapshot([record]), now: now)
        #expect(graph.nodes.first { $0.kind == .service }?.cpuPct == nil)
        #expect(graph.nodes.first { $0.kind == .service }?.memMB == nil)
        #expect(graph.validUntil == now.addingTimeInterval(5))
        let expired = FleetTopology(snapshot: snapshot([record]), now: now.addingTimeInterval(6))
        #expect(!expired.isStale)
        #expect(expired.edges.map(\.kind) == [.owns])
    }

    @Test func thousandServicesHaveBoundedProjection() {
        let records = (0..<1000).map { service("service-\($0)", owner: "owner-\($0 % 10)") }
        let started = Date()
        let graph = FleetTopology(snapshot: snapshot(records), now: now)
        print("Topology 1000 services: \(Date().timeIntervalSince(started))s, \(graph.nodes.count) nodes")
        #expect(graph.nodes.count == 3010)
        #expect(graph.edges.count == 3000)
    }

    @Test func sessionsUseReconciliationTimeInsteadOfPublicationTime() {
        let session = AgentSession(id: "session", tool: "ouros", pid: 42, cpuPct: 3, memMB: 10)
        var value = snapshot([], sessions: [session])
        let missing = FleetTopology(snapshot: value, now: now)
        #expect(missing.nodes.first?.cpuPct == nil)
        #expect(missing.nodes.first?.observedAt == nil)
        value.daemon.lastReconcileAt = now.addingTimeInterval(-20)
        let stale = FleetTopology(snapshot: value, now: now)
        #expect(!stale.isStale)
        #expect(stale.nodes.first?.cpuPct == nil)
        value.daemon.lastReconcileAt = now.addingTimeInterval(-10)
        let fresh = FleetTopology(snapshot: value, now: now)
        #expect(fresh.nodes.first?.cpuPct == 3)
        #expect(fresh.nodes.first?.observedAt == now.addingTimeInterval(-10))
        #expect(fresh.validUntil == now.addingTimeInterval(5))
    }

}
