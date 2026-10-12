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

    @Test func windowFloorReservesTheNewBottomStrip() {
        #expect(ConsoleLayout.minimumContentHeight >= ConsoleLayout.titlebarReserve
                + ConsoleLayout.moduleHeaderHeight + ConsoleLayout.cardHeight
                + ConsoleLayout.moduleBottomPadding + 44)
    }
}
