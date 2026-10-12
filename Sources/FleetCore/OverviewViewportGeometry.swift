import CoreGraphics

/// Overview receives the module viewport after the titlebar and dashboard footer
/// have taken their space. Reserve the readable chrome first; charts spend what
/// remains, and the process preview declares its cap rather than scrolling.
public struct OverviewViewportGeometry: Sendable {
    public static let horizontalPadding: CGFloat = 21
    public static let verticalPadding: CGFloat = 13
    public static let gap: CGFloat = 10
    public static let minimumPlotHeight: CGFloat = 89

    public let contentWidth: CGFloat
    public let primaryColumns: Int
    public let controlsStacked: Bool
    public let secondaryColumns: Int
    public let plotHeight: CGFloat
    public let processLimit: Int
    public let requiredHeight: CGFloat

    public init(viewport: CGSize, focused: Bool = false, instrumentCount: Int = 4,
                verticalSafeArea: CGFloat = 0) {
        // NavigationSplitView includes its toolbar safe area in the geometry
        // proposal. That obscured space cannot be spent on chart height.
        let availableHeight = max(0, viewport.height - max(0, verticalSafeArea))
        contentWidth = DashboardContentGeometry.width(available: viewport.width - Self.horizontalPadding * 2)
        primaryColumns = focused || contentWidth < 600 ? 1 : 2
        controlsStacked = contentWidth < 840
        let count = max(1, instrumentCount)
        // Five concise readings still fit beside the Details action with the
        // sidebar open; wrapping that glance would spend another chart's height.
        secondaryColumns = min(count, max(1, Int((contentWidth + Self.gap) / 130)))
        let secondaryRows = (count + secondaryColumns - 1) / secondaryColumns
        let primaryRows = focused || primaryColumns == 2 ? 1 : 2
        let cellWidth = (contentWidth - CGFloat(primaryColumns - 1) * Self.gap) / CGFloat(primaryColumns)
        // The memory facts wrap in narrower cards; CPU's core grid is shorter.
        let primaryChrome: CGFloat = cellWidth >= 420 ? 139 : 179
        let fixedHeight = Self.verticalPadding * 2 + 32 + (controlsStacked ? 50 : 22)
            + CGFloat(secondaryRows) * 58 + CGFloat(secondaryRows - 1) * Self.gap
            + 14 + Self.gap * 5 + CGFloat(primaryRows) * primaryChrome
            + CGFloat(primaryRows - 1) * Self.gap + 86
        var limit = availableHeight >= 740 ? 5 : 3
        while limit > 1 && fixedHeight + CGFloat(limit) * 28
            + CGFloat(primaryRows) * Self.minimumPlotHeight > availableHeight {
            limit -= 1
        }
        processLimit = limit
        let maximumPlot: CGFloat = focused ? 377 : 233
        plotHeight = min(maximumPlot, max(Self.minimumPlotHeight,
            (availableHeight - fixedHeight - CGFloat(limit) * 28) / CGFloat(primaryRows)))
        requiredHeight = fixedHeight + CGFloat(limit) * 28 + CGFloat(primaryRows) * plotHeight
    }
}
