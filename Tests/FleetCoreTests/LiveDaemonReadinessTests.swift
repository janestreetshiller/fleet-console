import XCTest
@testable import FleetCore

final class LiveDaemonReadinessTests: XCTestCase {
    func testOnlyARecentSnapshotOnTheCurrentConnectionIsReady() {
        for age in [0.0, 0.25, 15.0] {
            XCTAssertTrue(LiveDaemonReadiness.snapshot(connected: true, hasDaemon: true, ageSeconds: age))
        }
        XCTAssertFalse(LiveDaemonReadiness.snapshot(connected: false, hasDaemon: true, ageSeconds: 0))
        for age in [-1.0, 15.001, Double.nan, .infinity, -.infinity] {
            XCTAssertFalse(LiveDaemonReadiness.snapshot(connected: true, hasDaemon: true, ageSeconds: age))
        }
    }

    func testConnectionWithoutAReceivedSnapshotIsNotReady() {
        XCTAssertFalse(LiveDaemonReadiness.snapshot(connected: true, hasDaemon: true, ageSeconds: nil))
        XCTAssertFalse(LiveDaemonReadiness.snapshot(connected: true, hasDaemon: false, ageSeconds: 0))
    }
}
