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
}
