import CoreGraphics
import Testing
@testable import FleetCore

struct OverviewViewportGeometryTests {
    @Test("The shipping split-view toolbar safe area is excluded from the chart budget")
    func toolbarSafeArea() {
        let layout = OverviewViewportGeometry(viewport: CGSize(width: 982, height: 680), verticalSafeArea: 40)
        let unobscured = OverviewViewportGeometry(viewport: CGSize(width: 982, height: 640))
        #expect(layout.processLimit == 3)
        #expect(layout.requiredHeight <= 640)
        #expect(layout.plotHeight == unobscured.plotHeight)
        #expect(layout.requiredHeight == unobscured.requiredHeight)
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
        let layout = OverviewViewportGeometry(viewport: CGSize(width: 709, height: 638), instrumentCount: 5)
        #expect(layout.primaryColumns == 2)
        #expect(layout.secondaryColumns == 5)
        #expect(layout.processLimit >= 1)
        #expect(layout.plotHeight >= 89)
        #expect(layout.requiredHeight <= 638)
    }

    @Test("Wide viewports retain full charts, five processes and the centered width cap")
    func standardViewport() {
        let layout = OverviewViewportGeometry(viewport: CGSize(width: 1560, height: 818))
        #expect(layout.contentWidth == 1100)
        #expect(layout.primaryColumns == 2)
        #expect(layout.processLimit == 5)
        #expect(layout.plotHeight == 233)
        #expect(layout.requiredHeight <= 818)
        let focused = OverviewViewportGeometry(viewport: CGSize(width: 1560, height: 818), focused: true)
        #expect(focused.primaryColumns == 1)
        #expect(focused.plotHeight > layout.plotHeight)
        #expect(focused.requiredHeight <= 818)
    }
}
