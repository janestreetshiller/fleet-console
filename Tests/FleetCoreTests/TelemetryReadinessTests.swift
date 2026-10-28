import XCTest
@testable import FleetCore

final class TelemetryReadinessTests: XCTestCase {
    func testRetainedHistoryCannotHideUnavailableCurrentRates() {
        for rate: Double? in [nil, -1, .nan, .infinity] {
            XCTAssertFalse(TelemetryReadiness.network(
                probeSucceeded: true, hasActiveLink: true,
                download: rate, upload: 0, historySamples: 30
            ))
            XCTAssertFalse(TelemetryReadiness.network(
                probeSucceeded: true, hasActiveLink: true,
                download: 0, upload: rate, historySamples: 30
            ))
        }
    }

    func testFailedProbeCannotPassWithCachedRates() {
        XCTAssertFalse(TelemetryReadiness.network(
            probeSucceeded: false, hasActiveLink: true,
            download: 10, upload: 10, historySamples: 30
        ))
        XCTAssertFalse(TelemetryReadiness.power(probeSucceeded: false, hasBattery: true, charge: 0.5))
    }

    func testInternalBatteryRequiresValidCharge() {
        XCTAssertTrue(TelemetryReadiness.power(probeSucceeded: true, hasBattery: true, charge: 0.5))
        XCTAssertTrue(TelemetryReadiness.power(probeSucceeded: true, hasBattery: true, charge: 0))
        XCTAssertTrue(TelemetryReadiness.power(probeSucceeded: true, hasBattery: true, charge: 1))
        for charge: Double? in [nil, -1, 2, .nan, .infinity] {
            XCTAssertFalse(TelemetryReadiness.power(probeSucceeded: true, hasBattery: true, charge: charge))
        }
    }

    func testDesktopPowerAbsenceIsDifferentFromAProbeFailure() {
        XCTAssertTrue(TelemetryReadiness.power(probeSucceeded: true, hasBattery: false, charge: nil))
        XCTAssertFalse(TelemetryReadiness.power(probeSucceeded: false, hasBattery: false, charge: nil))
    }

    func testSuccessfulReadWithoutAPhysicalLinkIsNotAProbeFailure() {
        XCTAssertTrue(TelemetryReadiness.network(
            probeSucceeded: true, hasActiveLink: false,
            download: nil, upload: nil, historySamples: 0
        ))
        XCTAssertFalse(TelemetryReadiness.network(
            probeSucceeded: false, hasActiveLink: false,
            download: nil, upload: nil, historySamples: 0
        ))
    }

    func testActiveLinkAcceptsAValidIdleInterval() {
        XCTAssertTrue(TelemetryReadiness.network(
            probeSucceeded: true, hasActiveLink: true,
            download: 0, upload: 0, historySamples: 1
        ))
    }

    func testActiveLinkRequiresCurrentRatesAndHistory() {
        XCTAssertFalse(TelemetryReadiness.network(
            probeSucceeded: true, hasActiveLink: true,
            download: nil, upload: nil, historySamples: 0
        ))
    }
}
