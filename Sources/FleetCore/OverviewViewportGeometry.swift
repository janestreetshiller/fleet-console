import CoreGraphics

/// Overview receives the module viewport after the toolbar has taken its space —
/// SwiftUI's geometry for the column already excludes the toolbar safe area.
/// Reserve the readable chrome first; the charts spend what remains, and the
/// process preview declares its cap rather than scrolling.
///
/// There is no page heading, footer line or caption row to pay for. Each was a
/// fixed cost charged to the plots, which is how a 1560-wide window ended up
/// drawing its two primary traces 82pt tall.
public struct OverviewViewportGeometry: Sendable {
    public static let horizontalPadding: CGFloat = 21
    public static let verticalPadding: CGFloat = 13
    public static let gap: CGFloat = 10
    public static let minimumPlotHeight: CGFloat = 89
    /// A trace taller than this stops adding legibility and starts adding air.
    public static let maximumPlotHeight: CGFloat = 377
    // Measured in the shipping window, not estimated: the surface renderer's
    // module column at 1560 and 982 wide, part by part.
    /// The secondary glance: one row of readings inside its card.
    public static let glanceRowHeight: CGFloat = 62
    /// The process card without rows: padding, title row and column labels.
    public static let processChrome: CGFloat = 60
    /// One process row and the spacing under it.
    public static let processRowHeight: CGFloat = 30
    /// A primary card around its plot: title, subtitle and the footer facts.
    /// Below `memoryFactsRowWidth` the memory facts take two rows of two.
    public static let primaryChromeWide: CGFloat = 145
    public static let primaryChromeNarrow: CGFloat = 173
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
        // Five concise readings still fit beside the Details action with the
        // sidebar open; wrapping that glance would spend another chart's height.
        secondaryColumns = min(count, max(1, Int((contentWidth + Self.gap) / 130)))
        let secondaryRows = (count + secondaryColumns - 1) / secondaryColumns
        let primaryRows = focused || primaryColumns == 2 ? 1 : 2
        let cellWidth = (contentWidth - CGFloat(primaryColumns - 1) * Self.gap) / CGFloat(primaryColumns)
        let primaryChrome = cellWidth >= Self.memoryFactsRowWidth
            ? Self.primaryChromeWide : Self.primaryChromeNarrow
        // Three stacked parts: primary cards, glance, processes. Overview's
        // controls live in the native toolbar, outside this viewport.
        let fixedHeight = Self.verticalPadding * 2 + Self.gap * 2
            + CGFloat(secondaryRows) * Self.glanceRowHeight + CGFloat(secondaryRows - 1) * Self.gap
            + CGFloat(primaryRows) * primaryChrome + CGFloat(primaryRows - 1) * Self.gap
            + Self.processChrome
        var limit = availableHeight >= 740 ? 5 : 3
        while limit > 1 && fixedHeight + CGFloat(limit) * Self.processRowHeight
            + CGFloat(primaryRows) * Self.minimumPlotHeight > availableHeight {
            limit -= 1
        }
        processLimit = limit
        // The plots take everything the fixed parts leave, so the page ends at
        // the window's edge instead of stopping short of it.
        plotHeight = min(Self.maximumPlotHeight, max(Self.minimumPlotHeight,
            (availableHeight - fixedHeight - CGFloat(limit) * Self.processRowHeight) / CGFloat(primaryRows)))
        requiredHeight = fixedHeight + CGFloat(limit) * Self.processRowHeight + CGFloat(primaryRows) * plotHeight
    }
}
