import CoreGraphics
import Testing
@testable import FleetCore

struct OverviewViewportGeometryTests {
    @Test("The plots spend the whole viewport instead of leaving a band under the page")
    func plotsFillTheViewport() {
        // 652 is the module column the shipping window hands Overview at its
        // 690pt rendering height, toolbar already excluded.
        let layout = OverviewViewportGeometry(viewport: CGSize(width: 1337, height: 652))
        #expect(layout.plotHeight > OverviewViewportGeometry.minimumPlotHeight)
        #expect(layout.plotHeight < OverviewViewportGeometry.maximumPlotHeight)
        #expect(abs(layout.requiredHeight - 652) < 1)
    }

    @Test("The compact module budgets both charts and an explicit process cap inside its viewport")
    func compactViewport() {
        let layout = OverviewViewportGeometry(viewport: CGSize(width: 982, height: 638))
        #expect(layout.primaryColumns == 2)
        #expect(layout.processLimit == 3)
        #expect(layout.plotHeight >= 89)
        #expect(layout.requiredHeight <= 638)
        #expect(layout.contentWidth == 940)
    }

    @Test("A revealed sidebar still leaves both primary plots and the battery glance inside the compact height")
    func compactSidebarWithBattery() {
        let layout = OverviewViewportGeometry(viewport: CGSize(width: 761, height: 652), instrumentCount: 5)
        #expect(layout.primaryColumns == 2)
        #expect(layout.secondaryColumns == 5)
        #expect(layout.processLimit >= 1)
        #expect(layout.plotHeight >= 89)
        #expect(layout.requiredHeight <= 652)
    }

    @Test("Wide viewports retain full charts, five processes and the centered width cap")
    func standardViewport() {
        let layout = OverviewViewportGeometry(viewport: CGSize(width: 1560, height: 848))
        #expect(layout.contentWidth == 1100)
        #expect(layout.primaryColumns == 2)
        #expect(layout.processLimit == 5)
        #expect(layout.plotHeight > 233)
        #expect(layout.requiredHeight <= 848)
        let focused = OverviewViewportGeometry(viewport: CGSize(width: 1560, height: 848), focused: true)
        #expect(focused.primaryColumns == 1)
        #expect(focused.plotHeight >= layout.plotHeight)
        #expect(focused.requiredHeight <= 848)
    }

    @Test("Very tall windows cap the trace height rather than stretching it")
    func tallViewportCapsPlots() {
        let layout = OverviewViewportGeometry(viewport: CGSize(width: 1560, height: 1600))
        #expect(layout.plotHeight == OverviewViewportGeometry.maximumPlotHeight)
    }
}
