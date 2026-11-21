import XCTest
@testable import FleetCore

final class TailscaleDateTests: XCTestCase {

    private let reference = Date(timeIntervalSince1970: 1_754_145_930)

    func testParsesInternetDateTimeWithoutFractionalSeconds() {
        let parsed = TailscaleClient.parseDate("2025-08-02T14:45:30Z")
        XCTAssertEqual(parsed?.timeIntervalSince1970, reference.timeIntervalSince1970)
    }

    func testParsesInternetDateTimeWithFractionalSeconds() {
        let parsed = TailscaleClient.parseDate("2025-08-02T14:45:30.250Z")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.timeIntervalSince1970 ?? 0,
                       reference.timeIntervalSince1970 + 0.25,
                       accuracy: 0.001)
    }

    func testFractionalSecondsSurviveTheFallbackOrder() {
        let withMillis = TailscaleClient.parseDate("2025-08-02T14:45:30.750Z")
        XCTAssertNotEqual(withMillis?.timeIntervalSince1970, reference.timeIntervalSince1970,
                          "milliseconds were dropped: the plain style parsed a fractional stamp")
    }

    func testGoZeroTimeIsNeverSeenRatherThanAnAncientDate() {
        XCTAssertNil(TailscaleClient.parseDate("0001-01-01T00:00:00Z"))
        XCTAssertNil(TailscaleClient.parseDate("0001-01-01T00:00:00.000Z"))
    }

    func testEmptyAndMissingAndMalformedAreNil() {
        XCTAssertNil(TailscaleClient.parseDate(nil))
        XCTAssertNil(TailscaleClient.parseDate(""))
        XCTAssertNil(TailscaleClient.parseDate("not a date"))
        XCTAssertNil(TailscaleClient.parseDate("2025-08-02"))
    }
}
