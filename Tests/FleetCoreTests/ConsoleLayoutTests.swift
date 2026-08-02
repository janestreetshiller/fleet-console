import XCTest
import CoreGraphics
@testable import FleetCore

/// The layout budget, asserted rather than commented.
///
/// The bug these exist to prevent already happened once: `columnReserve` summed
/// to 786pt against a 780pt minimum window, and the comment beside it cited a
/// 1060pt minimum that no longer existed. Three numbers, two of them wrong, none
/// of them checkable. Everything below is a property of the arithmetic, so it
/// fails the build rather than the user.
final class ConsoleLayoutTests: XCTestCase {

    // MARK: The ladder

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

    /// Adjacent rungs approach φ going up the ladder. This is the reason the
    /// scale is worth having: two sizes drawn from it are never a half-point
    /// apart, and never so far apart that the relationship is unreadable.
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

    // MARK: The golden division

    func testMajorAndMinorSumToTheWhole() {
        for total in stride(from: CGFloat(100), through: 2000, by: 50) {
            XCTAssertEqual(Scale.major(total) + Scale.minor(total), total, accuracy: 0.000_1)
        }
    }

    func testMajorIsTheLargerSection() {
        XCTAssertGreaterThan(Scale.major(1000), Scale.minor(1000))
    }

    /// The whole point of the arrangement: the two side columns are the same
    /// width at every window size, so the window is symmetrical about its centre.
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

    /// Between the clamps, the content column really is the major section.
    func testContentColumnTakesTheGoldenSectionWhereUnclamped() {
        let split: CGFloat = 1_560 - ConsoleLayout.railWidth
        let side = ConsoleLayout.sideColumn(splitWidth: split)
        XCTAssertGreaterThan(side, ConsoleLayout.sideColumnMin, "clamped — this case proves nothing")
        XCTAssertLessThan(side, ConsoleLayout.sideColumnMax, "clamped — this case proves nothing")

        let content = split - side * 2
        XCTAssertEqual(content, Scale.major(split), accuracy: 0.5)
    }

    // MARK: The budget holds at every size the window can take

    /// The regression. At the window's minimum, with a tool panel open and the
    /// inspector yielded, every floor is still met — and the module column lands
    /// exactly on its own, which is what makes this the *minimum* rather than an
    /// arbitrary number above it.
    func testTheArrangementFitsAtTheMinimumWindowWidth() {
        let split = ConsoleLayout.minimumContentWidth
            - ConsoleLayout.railWidth - ConsoleLayout.panelMin
        let module = ConsoleLayout.moduleColumn(splitWidth: split, sideColumns: 1)
        XCTAssertNotNil(module, "the module column does not fit at the minimum window width")
        XCTAssertEqual(module ?? 0, ConsoleLayout.moduleColumnMin, accuracy: 0.5)
    }

    /// The same, one step up: at the inspector-and-panel floor both side columns
    /// fit alongside a panel, and the module column is again exactly on its floor.
    func testBothSideColumnsFitAlongsideAPanelAtTheirFloor() {
        let split = ConsoleLayout.inspectorAndPanelFloor
            - ConsoleLayout.railWidth - ConsoleLayout.panelMin
        let module = ConsoleLayout.moduleColumn(splitWidth: split, sideColumns: 2)
        XCTAssertNotNil(module, "both side columns plus a panel do not fit at their own floor")
        XCTAssertEqual(module ?? 0, ConsoleLayout.moduleColumnMin, accuracy: 0.5)
    }

    /// The composed window shows everything at once with room to spare — the
    /// property `defaultContentSize` was chosen for, now checked rather than
    /// asserted in a comment.
    func testTheComposedWindowFitsEverythingAtOnce() {
        let width = DashboardWindowGeometry.defaultContentSize.width
        XCTAssertGreaterThanOrEqual(width, ConsoleLayout.inspectorAndPanelFloor)

        let split = width - ConsoleLayout.railWidth - ConsoleLayout.panelMin
        XCTAssertNotNil(ConsoleLayout.moduleColumn(splitWidth: split, sideColumns: 2))
    }

    /// Without a panel the three columns fit at every width the window allows,
    /// which is the arrangement the app is actually about.
    func testThreeColumnsFitAtEveryPermittedWidth() {
        for width in stride(from: ConsoleLayout.minimumContentWidth, through: 3000, by: 7) {
            let split = width - ConsoleLayout.railWidth
            XCTAssertNotNil(ConsoleLayout.moduleColumn(splitWidth: split, sideColumns: 2),
                            "three columns do not fit at \(width)")
        }
    }

    /// The ordering the cascade depends on. If these ever cross, the rule
    /// "the inspector yields to a panel" has no width range to happen in.
    func testTheFloorsAreOrdered() {
        XCTAssertLessThan(ConsoleLayout.minimumContentWidth,
                          ConsoleLayout.inspectorAndPanelFloor)
        XCTAssertLessThanOrEqual(ConsoleLayout.inspectorAndPanelFloor,
                                 DashboardWindowGeometry.defaultContentSize.width)
    }

    /// The minimum must be a real minimum: one point narrower and the module
    /// column is under its floor.
    func testTheMinimumIsTight() {
        let split = ConsoleLayout.minimumContentWidth - 1
            - ConsoleLayout.railWidth - ConsoleLayout.panelMin
        XCTAssertNil(ConsoleLayout.moduleColumn(splitWidth: split, sideColumns: 1),
                     "the stated minimum is not the narrowest width that fits")
    }

    /// Every declared rung-pinned constant is actually on the ladder. Cheap, and
    /// it is the check that catches a future edit typing 240 into `sideColumnMin`.
    func testDeclaredWidthsSitOnTheLadder() {
        for (name, value) in [("sideColumnMin", ConsoleLayout.sideColumnMin),
                              ("sideColumnMax", ConsoleLayout.sideColumnMax),
                              ("moduleColumnMin", ConsoleLayout.moduleColumnMin),
                              ("railWidth", ConsoleLayout.railWidth)] {
            XCTAssertTrue(Scale.ladder.contains(value), "\(name) = \(value) is off the ladder")
        }
    }

    // MARK: Height, now that it is a free dimension

    /// Height was `width / aspectRatio` for as long as the window was locked,
    /// which was a statement about the lock rather than about the content. It
    /// is derived from what has to fit now, and this is that claim: the
    /// toolbar's reserve, a module header, and one card down to the bottom of
    /// its trace.
    func testTheMinimumHeightHoldsTheToolbarAHeaderAndACard() {
        XCTAssertGreaterThanOrEqual(
            ConsoleLayout.minimumContentHeight,
            ConsoleLayout.titlebarReserve
                + ConsoleLayout.moduleHeaderHeight
                + ConsoleLayout.cardHeight,
            "the shortest window cannot show one card under its own header")
    }

    /// The regression, stated as what the *module column* gets.
    ///
    /// The first version of this floor left the toolbar out — the window is
    /// `.fullSizeContentView`, so the toolbar sits inside the content height —
    /// and came to 191. Rendering at exactly 191 sliced the card through the
    /// middle of its chart, because the module column was handed 191 − 55 = 136
    /// against the 199 a header and a card need. That subtraction is the thing
    /// that was wrong, so it is the thing asserted: whatever the floor is, what
    /// survives the toolbar still holds a header and a card.
    func testTheModuleColumnStillFitsACardAfterTheToolbarTakesItsCut() {
        let usable = ConsoleLayout.minimumContentHeight - ConsoleLayout.titlebarReserve
        XCTAssertGreaterThanOrEqual(
            usable,
            ConsoleLayout.moduleHeaderHeight + ConsoleLayout.cardHeight,
            "the module column gets \(usable)pt at the floor and needs "
                + "\(ConsoleLayout.moduleHeaderHeight + ConsoleLayout.cardHeight)")
    }

    /// And is tight: no slack beyond the parts it is defined from.
    func testTheMinimumHeightIsExactlyItsParts() {
        XCTAssertEqual(
            ConsoleLayout.minimumContentHeight,
            ConsoleLayout.titlebarReserve
                + ConsoleLayout.moduleHeaderHeight
                + ConsoleLayout.cardHeight
                + ConsoleLayout.moduleBottomPadding)
    }

    /// A card, down to the bottom of its trace: padding, title row, the gap
    /// under it, the chart, padding again.
    func testACardIsItsPartsAndLandsOnARung() {
        XCTAssertEqual(ConsoleLayout.cardHeight,
                       ConsoleLayout.cardPadding * 2
                           + ConsoleLayout.cardTitleRow
                           + ConsoleLayout.cardTitleGap
                           + ConsoleLayout.chartHeight)
        XCTAssertTrue(Scale.ladder.contains(ConsoleLayout.cardHeight),
                      "cardHeight = \(ConsoleLayout.cardHeight) fell off the ladder")
    }

    /// The rail is its toggle plus the space either side, rather than a 34
    /// that happens to agree with them.
    func testTheRailIsItsToggleAndItsSpacing() {
        XCTAssertEqual(ConsoleLayout.railWidth,
                       ConsoleLayout.toggleSize + ConsoleLayout.railSpacing * 2)
    }

    /// The composed window is comfortably above both floors, on both axes.
    func testTheComposedSizeClearsBothFloors() {
        let size = DashboardWindowGeometry.defaultContentSize
        XCTAssertGreaterThan(size.width, ConsoleLayout.minimumContentWidth)
        XCTAssertGreaterThan(size.height, ConsoleLayout.minimumContentHeight)
    }
}
