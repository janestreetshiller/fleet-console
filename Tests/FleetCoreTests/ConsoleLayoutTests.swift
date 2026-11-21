import XCTest
import CoreGraphics
@testable import FleetCore

final class ConsoleLayoutTests: XCTestCase {

    func testLadderIsFibonacci() {
        let ladder = Scale.ladder
        XCTAssertGreaterThan(ladder.count, 3)
        for index in 2..<ladder.count {
            XCTAssertEqual(ladder[index], ladder[index - 1] + ladder[index - 2],
                           "rung \(index) (\(ladder[index])) is not the sum of the two below it")
        }
    }

    func testLadderIsAscendingAndPositive() {
        XCTAssertEqual(Scale.ladder, Scale.ladder.sorted())
        XCTAssertEqual(Set(Scale.ladder).count, Scale.ladder.count, "a rung is repeated")
        XCTAssertTrue(Scale.ladder.allSatisfy { $0 > 0 })
    }

    func testUpperLadderRatiosConvergeOnPhi() {
        let upper = Scale.ladder.filter { $0 >= 21 }
        for (index, value) in upper.enumerated() where index > 0 {
            XCTAssertEqual(value / upper[index - 1], Scale.phi, accuracy: 0.01)
        }
    }

    func testSnapLandsOnARung() {
        for value in stride(from: CGFloat(1), through: 987, by: 7) {
            XCTAssertTrue(Scale.ladder.contains(Scale.snap(value)),
                          "\(value) snapped off the ladder")
        }
    }

    func testSnapPicksTheNearestRung() {
        XCTAssertEqual(Scale.snap(236), 233)
        XCTAssertEqual(Scale.snap(88), 89)
        XCTAssertEqual(Scale.snap(20), 21)
        XCTAssertEqual(Scale.snap(12), 13)
    }

    func testMajorAndMinorSumToTheWhole() {
        for total in stride(from: CGFloat(100), through: 2000, by: 50) {
            XCTAssertEqual(Scale.major(total) + Scale.minor(total), total, accuracy: 0.000_1)
        }
    }

    func testMajorIsTheLargerSection() {
        XCTAssertGreaterThan(Scale.major(1000), Scale.minor(1000))
    }

    func testSideColumnsAreMirroredAtEveryWidth() {
        for width in stride(from: ConsoleLayout.minimumContentWidth, through: 3000, by: 13) {
            let left = ConsoleLayout.sideColumn(splitWidth: width)
            let right = ConsoleLayout.sideColumn(splitWidth: width)
            XCTAssertEqual(left, right, "side columns diverged at \(width)")
        }
    }

    func testSideColumnHonoursItsFloorAndCeiling() {
        for width in stride(from: CGFloat(400), through: 4000, by: 11) {
            let side = ConsoleLayout.sideColumn(splitWidth: width)
            XCTAssertGreaterThanOrEqual(side, ConsoleLayout.sideColumnMin)
            XCTAssertLessThanOrEqual(side, ConsoleLayout.sideColumnMax)
        }
    }

    func testContentColumnTakesTheGoldenSectionWhereUnclamped() {
        let split: CGFloat = 1_560 - ConsoleLayout.railWidth
        let side = ConsoleLayout.sideColumn(splitWidth: split)
        XCTAssertGreaterThan(side, ConsoleLayout.sideColumnMin, "clamped — this case proves nothing")
        XCTAssertLessThan(side, ConsoleLayout.sideColumnMax, "clamped — this case proves nothing")

        let content = split - side * 2
        XCTAssertEqual(content, Scale.major(split), accuracy: 0.5)
    }

    func testTheArrangementFitsAtTheMinimumWindowWidth() {
        let split = ConsoleLayout.minimumContentWidth
            - ConsoleLayout.railWidth - ConsoleLayout.panelMin
        let module = ConsoleLayout.moduleColumn(splitWidth: split, sideColumns: 1)
        XCTAssertNotNil(module, "the module column does not fit at the minimum window width")
        XCTAssertEqual(module ?? 0, ConsoleLayout.moduleColumnMin, accuracy: 0.5)
    }

    func testBothSideColumnsFitAlongsideAPanelAtTheirFloor() {
        let split = ConsoleLayout.inspectorAndPanelFloor
            - ConsoleLayout.railWidth - ConsoleLayout.panelMin
        let module = ConsoleLayout.moduleColumn(splitWidth: split, sideColumns: 2)
        XCTAssertNotNil(module, "both side columns plus a panel do not fit at their own floor")
        XCTAssertEqual(module ?? 0, ConsoleLayout.moduleColumnMin, accuracy: 0.5)
    }

    func testTheComposedWindowFitsEverythingAtOnce() {
        let width = DashboardWindowGeometry.defaultContentSize.width
        XCTAssertGreaterThanOrEqual(width, ConsoleLayout.inspectorAndPanelFloor)

        let split = width - ConsoleLayout.railWidth - ConsoleLayout.panelMin
        XCTAssertNotNil(ConsoleLayout.moduleColumn(splitWidth: split, sideColumns: 2))
    }

    func testThreeColumnsFitAtEveryPermittedWidth() {
        for width in stride(from: ConsoleLayout.minimumContentWidth, through: 3000, by: 7) {
            let split = width - ConsoleLayout.railWidth
            XCTAssertNotNil(ConsoleLayout.moduleColumn(splitWidth: split, sideColumns: 2),
                            "three columns do not fit at \(width)")
        }
    }

    func testTheFloorsAreOrdered() {
        XCTAssertLessThan(ConsoleLayout.minimumContentWidth,
                          ConsoleLayout.inspectorAndPanelFloor)
        XCTAssertLessThanOrEqual(ConsoleLayout.inspectorAndPanelFloor,
                                 DashboardWindowGeometry.defaultContentSize.width)
    }

    func testTheMinimumIsTight() {
        let split = ConsoleLayout.minimumContentWidth - 1
            - ConsoleLayout.railWidth - ConsoleLayout.panelMin
        XCTAssertNil(ConsoleLayout.moduleColumn(splitWidth: split, sideColumns: 1),
                     "the stated minimum is not the narrowest width that fits")
    }

    func testDeclaredWidthsSitOnTheLadder() {
        for (name, value) in [("sideColumnMin", ConsoleLayout.sideColumnMin),
                              ("sideColumnMax", ConsoleLayout.sideColumnMax),
                              ("moduleColumnMin", ConsoleLayout.moduleColumnMin),
                              ("railWidth", ConsoleLayout.railWidth)] {
            XCTAssertTrue(Scale.ladder.contains(value), "\(name) = \(value) is off the ladder")
        }
    }

    func testTheMinimumHeightHoldsTheToolbarAHeaderAndACard() {
        XCTAssertGreaterThanOrEqual(
            ConsoleLayout.minimumContentHeight,
            ConsoleLayout.titlebarReserve
                + ConsoleLayout.moduleHeaderHeight
                + ConsoleLayout.cardHeight,
            "the shortest window cannot show one card under its own header")
    }

    func testTheModuleColumnStillFitsACardAfterTheToolbarTakesItsCut() {
        let usable = ConsoleLayout.minimumContentHeight - ConsoleLayout.titlebarReserve
        XCTAssertGreaterThanOrEqual(
            usable,
            ConsoleLayout.moduleHeaderHeight + ConsoleLayout.cardHeight,
            "the module column gets \(usable)pt at the floor and needs "
                + "\(ConsoleLayout.moduleHeaderHeight + ConsoleLayout.cardHeight)")
    }

    func testTheMinimumHeightIsExactlyItsParts() {
        XCTAssertEqual(
            ConsoleLayout.minimumContentHeight,
            ConsoleLayout.titlebarReserve
                + ConsoleLayout.moduleHeaderHeight
                + ConsoleLayout.cardHeight
                + ConsoleLayout.moduleBottomPadding)
    }

    func testACardIsItsPartsAndLandsOnARung() {
        XCTAssertEqual(ConsoleLayout.cardHeight,
                       ConsoleLayout.cardPadding * 2
                           + ConsoleLayout.cardTitleRow
                           + ConsoleLayout.cardTitleGap
                           + ConsoleLayout.chartHeight)
        XCTAssertTrue(Scale.ladder.contains(ConsoleLayout.cardHeight),
                      "cardHeight = \(ConsoleLayout.cardHeight) fell off the ladder")
    }

    func testTheRailIsItsToggleAndItsSpacing() {
        XCTAssertEqual(ConsoleLayout.railWidth,
                       ConsoleLayout.toggleSize + ConsoleLayout.railSpacing * 2)
    }

    func testTheComposedSizeClearsBothFloors() {
        let size = DashboardWindowGeometry.defaultContentSize
        XCTAssertGreaterThan(size.width, ConsoleLayout.minimumContentWidth)
        XCTAssertGreaterThan(size.height, ConsoleLayout.minimumContentHeight)
    }
}
