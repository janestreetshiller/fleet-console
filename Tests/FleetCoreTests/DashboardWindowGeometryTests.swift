import XCTest
@testable import FleetCore

/// What is left to assert about the console's opening size now that it is only
/// an opening size.
///
/// These used to check `contentAspectRatio` against the composed size and that
/// it was landscape. Both were properties of the aspect lock, and the lock is
/// gone: `contentAspectRatio` existed solely to be handed to
/// `NSWindow.contentAspectRatio`, so it went with it rather than staying as a
/// constant nothing reads, proved by a test that a division still works.
final class DashboardWindowGeometryTests: XCTestCase {
    func testTheOpeningSizeIsLandscape() {
        let size = DashboardWindowGeometry.defaultContentSize
        XCTAssertGreaterThan(size.width, size.height,
                             "the three-column arrangement wants width")
    }

    /// The floors are `ConsoleLayout`'s. This is the half that matters once the
    /// window can be dragged: it opens at neither floor, so there is room to
    /// shrink in both directions rather than one.
    func testTheOpeningSizeIsNotAtEitherFloor() {
        let size = DashboardWindowGeometry.defaultContentSize
        XCTAssertGreaterThan(size.width, ConsoleLayout.minimumContentWidth)
        XCTAssertGreaterThan(size.height, ConsoleLayout.minimumContentHeight)
    }
}
