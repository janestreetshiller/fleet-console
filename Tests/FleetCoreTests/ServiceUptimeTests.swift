import XCTest
@testable import FleetCore

final class ServiceUptimeTests: XCTestCase {

    private func record(state: ServiceState,
                        startedAgo: TimeInterval,
                        updatedAgo: TimeInterval) -> ServiceRecord {
        var record = ServiceRecord(
            id: "svc-test", friendlyName: "test", ownerAgent: "claude",
            purpose: "unit test", command: ["true"], cwd: "/tmp",
            startedAt: Date().addingTimeInterval(-startedAgo),
            leaseExpiresAt: Date().addingTimeInterval(3_600), leaseTTLSec: 3_600,
            state: state)
        record.updatedAt = Date().addingTimeInterval(-updatedAgo)
        return record
    }

    func testTerminalStatesFreezeUptimeAtTheTransition() {
        for state in [ServiceState.stopped, .crashed] {
            let subject = record(state: state, startedAgo: 7_200, updatedAgo: 3_600)
            XCTAssertEqual(subject.uptime, 3_600, accuracy: 2,
                           "\(state.rawValue) kept counting past the moment it ended")
        }
    }

    func testLiveStatesKeepCounting() {
        for state in [ServiceState.running, .healthy, .degraded, .starting] {
            let subject = record(state: state, startedAgo: 7_200, updatedAgo: 3_600)
            XCTAssertEqual(subject.uptime, 7_200, accuracy: 2,
                           "\(state.rawValue) stopped counting while still running")
        }
    }

    func testExpiredAndPausedAreNotTerminalAndKeepCounting() {
        for state in [ServiceState.expired, .paused, .expiring] {
            XCTAssertFalse(state.isTerminal, "\(state.rawValue) must not be terminal")
            let subject = record(state: state, startedAgo: 7_200, updatedAgo: 3_600)
            XCTAssertEqual(subject.uptime, 7_200, accuracy: 2)
        }
    }

    func testUptimeNeverGoesNegative() {
        let subject = record(state: .crashed, startedAgo: 60, updatedAgo: 3_600)
        XCTAssertEqual(subject.uptime, 0, accuracy: 0.001)
    }

    func testOnlyStoppedAndCrashedAreTerminal() {
        let terminal = ServiceState.allCases.filter(\.isTerminal)
        XCTAssertEqual(Set(terminal), [.stopped, .crashed])
    }
}
