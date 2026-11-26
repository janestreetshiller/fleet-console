import Foundation
import Testing
import FleetCore
@testable import FleetConsoleApp

@Suite(.serialized)
struct SnapshotRecoveryTests {
    @MainActor @Test("A decoded controller snapshot clears stale connection failure", arguments: [false, true])
    func healthySnapshotRecoversConnection(wasConnected: Bool) throws {
        let model = AppModel()
        model.connected = wasConnected
        model.connectionError = "The refresh request timed out."
        #expect(model.lastSnapshotReceivedUptime == nil)
        model.actionError = "A separate service action failed."
        let snapshot = Snapshot(daemon: DaemonInfo(version: "1.1.0", pid: 123,
                                                    startedAt: Date().addingTimeInterval(-60)))
        let decoded = try Codec.decode(Snapshot.self, from: Codec.encode(snapshot))

        model.apply(decoded)

        #expect(model.connected)
        #expect(model.connectionError == nil)
        #expect(model.lastSnapshotReceivedUptime != nil)
        #expect(model.daemon?.pid == 123)
        #expect(model.actionError == "A separate service action failed.")
    }

    @MainActor @Test func topologyEvidenceRequiresSnapshotAfterReconnect() throws {
        let model = AppModel(connectToController: false)
        let now = Date()
        let record = ServiceRecord(friendlyName: "API", ownerAgent: "Codex", purpose: "Serve project",
                                   command: ["api"], cwd: "/work/api", pid: 42, pgid: 42,
                                   startSignature: "recorded start", leaseExpiresAt: now.addingTimeInterval(60),
                                   leaseTTLSec: 60, state: .running,
                                   evidence: Evidence(processExists: true, listeningPorts: [8080], portScanRan: true,
                                                      checkedAt: now, leaderVerifiedAt: now))
        let snapshot = Snapshot(generatedAt: now, daemon: DaemonInfo(version: "test", pid: 123, startedAt: now),
                                services: [record])
        model.apply(snapshot)
        #expect(model.topology?.edges.map(\.kind) == [.owns, .verifiedLeader, .observedListener])

        model.setConnection(false, error: "Connection closed")
        let retained = try #require(model.topology)
        #expect(retained.isStale)
        #expect(retained.validUntil == nil)
        #expect(retained.nodes.map(\.kind) == [.owner, .service])
        #expect(retained.edges.map(\.kind) == [.owns])
        #expect(retained.limitations.contains { $0.contains("retained from the last snapshot") })

        model.setConnection(true, error: nil)
        #expect(model.topology == retained)

        model.apply(snapshot)
        #expect(model.topology?.edges.map(\.kind) == [.owns, .verifiedLeader, .observedListener])
    }
}
