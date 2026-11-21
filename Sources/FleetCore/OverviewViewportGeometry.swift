import CoreGraphics

public struct OverviewViewportGeometry: Sendable {
    public static let horizontalPadding: CGFloat = 21
    public static let verticalPadding: CGFloat = 13
    public static let gap: CGFloat = 10
    public static let headingHeight: CGFloat = 48
    public static let minimumPlotHeight: CGFloat = 89
    public static let maximumPlotHeight: CGFloat = 377
    public static let glanceRowHeight: CGFloat = 62
    public static let processChrome: CGFloat = 60
    public static let processRowHeight: CGFloat = 30
    public static let primaryChromeWide: CGFloat = 153
    public static let primaryChromeNarrow: CGFloat = 181
    public static let memoryFactsRowWidth: CGFloat = 340

    public let contentWidth: CGFloat
    public let primaryColumns: Int
    public let secondaryColumns: Int
    public let plotHeight: CGFloat
    public let processLimit: Int
    public let requiredHeight: CGFloat

    public init(viewport: CGSize, focused: Bool = false, instrumentCount: Int = 4) {
        let availableHeight = max(0, viewport.height)
        contentWidth = DashboardContentGeometry.width(available: viewport.width - Self.horizontalPadding * 2)
        primaryColumns = focused || contentWidth < 600 ? 1 : 2
        let count = max(1, instrumentCount)
        secondaryColumns = min(count, max(1, Int((contentWidth + Self.gap) / 130)))
        let secondaryRows = (count + secondaryColumns - 1) / secondaryColumns
        let primaryRows = focused || primaryColumns == 2 ? 1 : 2
        let cellWidth = (contentWidth - CGFloat(primaryColumns - 1) * Self.gap) / CGFloat(primaryColumns)
        let primaryChrome = cellWidth >= Self.memoryFactsRowWidth
            ? Self.primaryChromeWide : Self.primaryChromeNarrow
        let fixedHeight = Self.verticalPadding * 2 + Self.headingHeight + Self.gap * 3
            + CGFloat(secondaryRows) * Self.glanceRowHeight + CGFloat(secondaryRows - 1) * Self.gap
            + CGFloat(primaryRows) * primaryChrome + CGFloat(primaryRows - 1) * Self.gap
            + Self.processChrome
        var limit = availableHeight >= 740 ? 5 : 3
        while limit > 1 && fixedHeight + CGFloat(limit) * Self.processRowHeight
            + CGFloat(primaryRows) * Self.minimumPlotHeight > availableHeight {
            limit -= 1
        }
        processLimit = limit
        plotHeight = min(Self.maximumPlotHeight, max(Self.minimumPlotHeight,
            (availableHeight - fixedHeight - CGFloat(limit) * Self.processRowHeight) / CGFloat(primaryRows)))
        requiredHeight = fixedHeight + CGFloat(limit) * Self.processRowHeight + CGFloat(primaryRows) * plotHeight
    }
}
