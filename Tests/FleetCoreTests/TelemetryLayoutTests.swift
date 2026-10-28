import XCTest
import CoreGraphics
@testable import FleetCore

final class TelemetryLayoutTests: XCTestCase {
    func testSixInstrumentsBalanceIntoTwoRows() {
        XCTAssertEqual(ConsoleLayout.telemetryColumns(contentWidth: 1_010, instrumentCount: 6,
                                                      minimumCardWidth: 320, gap: 13), 3)
    }

    func testNarrowGridNeverShrinksCardsToFitAnExtraColumn() {
        XCTAssertEqual(ConsoleLayout.telemetryColumns(contentWidth: 630, instrumentCount: 6,
                                                      minimumCardWidth: 320, gap: 13), 1)
    }

    func testFiveInstrumentsAvoidOneOrphanInThreeColumns() {
        XCTAssertEqual(ConsoleLayout.telemetryColumns(contentWidth: 1_010, instrumentCount: 5,
                                                      minimumCardWidth: 320, gap: 13), 3)
    }

    func testFourInstrumentsAvoidOneOrphanInThreeColumns() {
        XCTAssertEqual(ConsoleLayout.telemetryColumns(contentWidth: 1_010, instrumentCount: 4,
                                                      minimumCardWidth: 320, gap: 13), 2)
    }
}
