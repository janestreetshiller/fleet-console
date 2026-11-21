import XCTest
@testable import FleetCore

final class LicenseTests: XCTestCase {

    private let suite = "fleetconsole.license.tests"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: suite)!
    }

    override func setUp() {
        super.setUp()
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    @MainActor
    private func makeManager(now: Date = Date()) -> LicenseManager {
        LicenseManager(defaults: defaults) { now }
    }

    @MainActor
    func testFirstLaunchStartsTrial() {
        let manager = makeManager()
        switch manager.status {
        case .trial(let days): XCTAssertEqual(days, TrialClock.periodDays)
        default: XCTFail("a fresh install is a trial, not \(manager.status)")
        }
    }

    @MainActor
    func testTrialStartPersistsAcrossInstances() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        _ = makeManager(now: start).status
        let again = makeManager(now: start)
        XCTAssertEqual(defaults.object(forKey: LicenseManager.trialStartKey) as? Date, start)
        _ = again.status
        XCTAssertEqual(defaults.object(forKey: LicenseManager.trialStartKey) as? Date, start,
                       "re-reading must not re-stamp the trial")
    }

    @MainActor
    func testTrialBoundary() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        _ = makeManager(now: start).status

        let day13 = makeManager(now: start + 13 * 86_400)
        guard case .trial(let days) = day13.status else {
            return XCTFail("day 13 is still a trial, not \(day13.status)")
        }
        XCTAssertEqual(days, 1)

        let day14 = makeManager(now: start + 14 * 86_400)
        guard case .expired = day14.status else {
            return XCTFail("day 14 is expired, not \(day14.status)")
        }
    }

    @MainActor
    func testBackwardsClockDoesNotExtendTrial() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        _ = makeManager(now: start + 13 * 86_400).status
        let manager = makeManager(now: start)
        guard case .trial(let days) = manager.status else {
            return XCTFail("a rewound clock is still the same trial")
        }
        XCTAssertEqual(days, TrialClock.periodDays)
    }

    func testTrialClockMath() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        XCTAssertEqual(TrialClock.daysRemaining(since: start, now: start), 14)
        XCTAssertEqual(TrialClock.daysRemaining(since: start, now: start + 86_399), 14)
        XCTAssertEqual(TrialClock.daysRemaining(since: start, now: start + 86_400), 13)
        XCTAssertEqual(TrialClock.daysRemaining(since: start, now: start + 14 * 86_400), 0)
        XCTAssertTrue(TrialClock.isActive(since: start, now: start + 13 * 86_400))
        XCTAssertFalse(TrialClock.isActive(since: start, now: start + 14 * 86_400))
        XCTAssertEqual(TrialClock.daysRemaining(since: start, now: start - 86_400), 14)
    }

    @MainActor
    func testTrialUnlocksPremiumFeatures() {
        let manager = makeManager()
        for feature in PremiumFeature.allCases {
            XCTAssertTrue(manager.isUnlocked(feature), "\(feature) is in the trial")
        }
    }

    @MainActor
    func testMITBuildKeepsEveryFeatureAfterTrialExpires() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        _ = makeManager(now: start).status
        let expired = makeManager(now: start + 15 * 86_400)
        for feature in PremiumFeature.allCases {
            XCTAssertTrue(expired.isUnlocked(feature), "MIT builds must never lock \(feature)")
        }
    }

    func testPremiumFeatureListIsComplete() {
        XCTAssertEqual(PremiumFeature.allCases.count, 4,
                       "gating lives in isUnlocked(_:); a new case must be deliberate")
    }

    func testSignedKeyValidates() {
        let key = "FLT1-" + LicenseKey.sign(payload: "2026-08-21")
        XCTAssertTrue(LicenseKey.isValid(key: key))
        XCTAssertNotNil(LicenseKey.issueDate(key: key))
    }

    func testSigningIsDeterministic() {
        XCTAssertEqual(LicenseKey.sign(payload: "2026-08-21"),
                       LicenseKey.sign(payload: "2026-08-21"))
    }

    func testWrongSecretRejects() {
        let key = "FLT1-" + LicenseKey.sign(payload: "2026-08-21", secret: "somebody-else")
        XCTAssertFalse(LicenseKey.isValid(key: key))
    }

    func testRejectsGarbage() {
        XCTAssertFalse(LicenseKey.isValid(key: ""))
        XCTAssertFalse(LicenseKey.isValid(key: "FLT1"))
        XCTAssertFalse(LicenseKey.isValid(key: "FLT1-no-signature"))
        XCTAssertFalse(LicenseKey.isValid(key: "FLT9-2026-08-21.AAAA"))
        XCTAssertFalse(LicenseKey.isValid(key: "FLT1-" + LicenseKey.sign(payload: "soon")))
    }

    func testTrimsWhitespace() {
        let key = "FLT1-" + LicenseKey.sign(payload: "2026-08-21")
        XCTAssertTrue(LicenseKey.isValid(key: "  \(key)\n"))
    }

    func testBase32RoundTrip() {
        for byteCount in [1, 2, 3, 4, 5, 8, 32] {
            let bytes = (0..<byteCount).map { UInt8($0 * 37 & 0xFF) }
            XCTAssertEqual(LicenseKey.decodeBase32(LicenseKey.encodeBase32(bytes))?.prefix(byteCount),
                           bytes[...])
        }
    }

    @MainActor
    func testInstallValidKey() {
        let manager = makeManager()
        XCTAssertTrue(manager.install(key: "FLT1-" + LicenseKey.sign(payload: "2026-08-21")))
        guard case .licensed = manager.status else {
            return XCTFail("a valid key licenses, not \(manager.status)")
        }
        XCTAssertTrue(manager.isUnlocked(.smcSensors))
        guard case .licensed = makeManager().status else {
            return XCTFail("the licence must persist across instances")
        }
    }

    @MainActor
    func testInstallInvalidKeyRefuses() {
        let manager = makeManager()
        XCTAssertFalse(manager.install(key: "FLT1-AAAA-AAAA-AAAA"))
        guard case .trial = manager.status else {
            return XCTFail("a refused key must not change the licence, got \(manager.status)")
        }
        XCTAssertNil(manager.installedKey)
    }

    @MainActor
    func testUninstallReturnsToTrial() {
        let manager = makeManager()
        XCTAssertTrue(manager.install(key: "FLT1-" + LicenseKey.sign(payload: "2026-08-21")))
        manager.uninstall()
        guard case .trial = manager.status else {
            return XCTFail("removing the key returns to the trial, got \(manager.status)")
        }
    }
}
