import XCTest
@testable import FleetCore

/// `TailscaleClient.parseDate` moved off `ISO8601DateFormatter` and onto
/// `Date.ISO8601FormatStyle` to get out from under shared mutable state. That is a
/// parser swap on a wire format we do not control, so the contract it has to keep
/// is written down here rather than assumed: both RFC 3339 shapes tailscale emits
/// still parse to the same instant, and Go's zero time still reads as "never".
final class TailscaleDateTests: XCTestCase {

    private let reference = Date(timeIntervalSince1970: 1_754_145_930)  // 2025-08-02T14:45:30Z

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

    /// The fractional style is tried first and the plain one second. If that order
    /// ever inverts, the fractional case above starts losing its milliseconds
    /// silently — so assert the two disagree, which is what makes the order matter.
    func testFractionalSecondsSurviveTheFallbackOrder() {
        let withMillis = TailscaleClient.parseDate("2025-08-02T14:45:30.750Z")
        XCTAssertNotEqual(withMillis?.timeIntervalSince1970, reference.timeIntervalSince1970,
                          "milliseconds were dropped: the plain style parsed a fractional stamp")
    }

    /// `0001-01-01T00:00:00Z` is Go's zero `time.Time`. It is what tailscale sends
    /// for a node it has never seen, and it is syntactically a perfectly good date,
    /// which is exactly why it has to be refused by name rather than by parsing.
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
