import Foundation
import CoreGraphics

public enum Scale {
    public static let phi: CGFloat = 1.618_033_988_749_895

    public static let ladder: [CGFloat] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89,
                                           144, 233, 377, 610, 987]

    public static func snap(_ value: CGFloat) -> CGFloat {
        guard let nearest = ladder.min(by: {
            abs($0 - value) < abs($1 - value)
        }) else { return value }
        return nearest
    }

    public static func major(_ total: CGFloat) -> CGFloat { total / phi }

    public static func minor(_ total: CGFloat) -> CGFloat { total - major(total) }
}

public enum ConsoleLayout {

    public static let sideColumnMin: CGFloat = 233
    public static let sideColumnMax: CGFloat = 377

    public static let moduleColumnMin: CGFloat = 377

    public static let railWidth: CGFloat = toggleSize + railSpacing * 2

    public static let panelMin: CGFloat = 40 * 8 + 17 + 1

    public static let minimumContentWidth: CGFloat =
        sideColumnMin + moduleColumnMin + railWidth + panelMin

    public static let inspectorAndPanelFloor: CGFloat =
        sideColumnMin * 2 + moduleColumnMin + railWidth + panelMin

    public static let chartHeight: CGFloat = 89
    public static let cardPadding: CGFloat = 13
    public static let toggleSize: CGFloat = 22
    public static let railSpacing: CGFloat = 6

    public static let cardTitleRow: CGFloat = 21
    public static let cardTitleGap: CGFloat = 8

    public static let cardHeight: CGFloat =
        cardPadding * 2 + cardTitleRow + cardTitleGap + chartHeight

    public static let titlebarReserve: CGFloat = 55

    public static let moduleHeaderHeight: CGFloat = 55

    public static let moduleBottomPadding: CGFloat = 21

    public static let minimumContentHeight: CGFloat =
        titlebarReserve + moduleHeaderHeight + cardHeight + moduleBottomPadding

    public static func telemetryColumns(contentWidth: CGFloat, instrumentCount: Int,
                                        minimumCardWidth: CGFloat, gap: CGFloat) -> Int {
        let fits = max(1, Int((max(0, contentWidth) + gap) / (minimumCardWidth + gap)))
        var columns = max(1, min(fits, instrumentCount))
        if columns >= 3 && instrumentCount % columns == 1 { columns -= 1 }
        return columns
    }

    public static func sideColumn(splitWidth: CGFloat) -> CGFloat {
        let ideal = Scale.minor(splitWidth) / 2
        return min(max(ideal, sideColumnMin), sideColumnMax)
    }

    public static func moduleColumn(splitWidth: CGFloat, sideColumns: Int) -> CGFloat? {
        let remaining = splitWidth - sideColumn(splitWidth: splitWidth) * CGFloat(sideColumns)
        return remaining >= moduleColumnMin ? remaining : nil
    }
}
