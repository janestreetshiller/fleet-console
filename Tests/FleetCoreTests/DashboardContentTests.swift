import CoreGraphics
import Testing
@testable import FleetCore

struct DashboardContentTests {
    @Test func contentIsContainedAndCenteredAtEveryWidth() {
        for available: CGFloat in [377, 720, 1_100, 1_600, 2_560] {
            let width = DashboardContentGeometry.width(available: available)
            let margin = DashboardContentGeometry.margin(available: available)
            #expect(width <= 1_100)
            #expect(width + margin * 2 == available)
            #expect(margin >= 0)
        }
    }

    /// The window has no footer strip any more; the floor pays for the
    /// titlebar, the module's control row and one card, and nothing else.
    @Test func windowFloorReservesNoFooterStrip() {
        #expect(ConsoleLayout.minimumContentHeight == ConsoleLayout.titlebarReserve
                + ConsoleLayout.moduleHeaderHeight + ConsoleLayout.cardHeight
                + ConsoleLayout.moduleBottomPadding)
    }
}
