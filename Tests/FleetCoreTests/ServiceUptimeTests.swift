import XCTest
@testable import FleetCore

/// `uptime` used to be `Date().timeIntervalSince(startedAt)` with no regard for
/// whether the process was still alive, so a crashed record kept accruing uptime
/// forever. That is the one thing this app is not allowed to do — state a fact
/// about a process it has no evidence for — so the boundary gets a test rather
/// than a comment.
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
            // Started two hours ago, went terminal one hour ago: it ran for an hour,
            // and it does not matter how long ago that was.
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

    /// An expired lease is not a stopped process — the reaper leaves a claimed
    /// record alone and reports it — and a paused one is resident and holding its
    /// ports. Neither has stopped running, so neither freezes.
    func testExpiredAndPausedAreNotTerminalAndKeepCounting() {
        for state in [ServiceState.expired, .paused, .expiring] {
            XCTAssertFalse(state.isTerminal, "\(state.rawValue) must not be terminal")
            let subject = record(state: state, startedAgo: 7_200, updatedAgo: 3_600)
            XCTAssertEqual(subject.uptime, 7_200, accuracy: 2)
        }
    }

    /// A clock adjustment can put `updatedAt` before `startedAt`. A negative
    /// duration renders as "-1h 4m", which reads as a bug in the app rather than a
    /// bug in the clock.
    func testUptimeNeverGoesNegative() {
        let subject = record(state: .crashed, startedAgo: 60, updatedAgo: 3_600)
        XCTAssertEqual(subject.uptime, 0, accuracy: 0.001)
    }

    /// The predicate the freeze depends on. If `.expired` were ever folded into
    /// `isTerminal`, an expired-but-running service would silently stop counting.
    func testOnlyStoppedAndCrashedAreTerminal() {
        let terminal = ServiceState.allCases.filter(\.isTerminal)
        XCTAssertEqual(Set(terminal), [.stopped, .crashed])
    }
}
