import XCTest
@testable import FleetCore

final class DashboardWindowGeometryTests: XCTestCase {
    func testTheOpeningSizeIsLandscape() {
        let size = DashboardWindowGeometry.defaultContentSize
        XCTAssertGreaterThan(size.width, size.height,
                             "the three-column arrangement wants width")
    }

    func testTheOpeningSizeIsNotAtEitherFloor() {
        let size = DashboardWindowGeometry.defaultContentSize
        XCTAssertGreaterThan(size.width, ConsoleLayout.minimumContentWidth)
        XCTAssertGreaterThan(size.height, ConsoleLayout.minimumContentHeight)
    }
}
