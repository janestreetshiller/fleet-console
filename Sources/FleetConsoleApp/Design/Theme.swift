import SwiftUI

enum FleetFont {
    static let title = Font.system(size: 14, weight: .semibold)
    static let rowTitle = Font.system(size: 13)
    static let rowTitleCompact = Font.system(size: 13)
    static let body = Font.system(size: 13)
    static let subtitle = Font.system(size: 12)
    static let caption = Font.system(size: 12)
    static let micro = Font.system(size: 11, weight: .medium)
    static let nano = Font.system(size: 11)
    static let chevron = Font.system(size: 10, weight: .semibold)
    static let marker = Font.system(size: 8)
    static let plateLabel = Font.system(size: 8, weight: .regular, design: .monospaced)
    static let sectionLabel = Font.system(size: 12, weight: .semibold)
    static let stat = Font.system(size: 22, weight: .semibold)

    static func mono(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum FleetMetrics {
    static let gutter: CGFloat = 16
    static let rowInset: CGFloat = 10
    static let rowHighlightMargin: CGFloat = 6
    static let rowGap: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 7
    static let compactRowHeight: CGFloat = 36

    static let iconCompact: CGFloat = 26
    static let iconRow: CGFloat = 28
    static let iconRowLarge: CGFloat = 30
    static let meterWidth: CGFloat = 54
    static let meterHeight: CGFloat = 5
    static let coreCellWidth: CGFloat = 7
    static let coreCellHeight: CGFloat = 22

    static let corner: CGFloat = 5
    static let tileCorner: CGFloat = 8
    static let tagCorner: CGFloat = 3
    static let barCorner: CGFloat = 2
    static let iconCornerRatio: CGFloat = 0.26
    static let iconGlyphRatio: CGFloat = 0.46
    static let iconBadgeRatio: CGFloat = 0.34
    static let iconBadgeRing: CGFloat = 1.5
    static let detailInset: CGFloat = 28
    static let verdictColumn: CGFloat = 8
    static let popoverWidth: CGFloat = 480
    static let popoverBodyHeight: CGFloat = 300
    static let iconButtonSize: CGFloat = 28
    static let actionSlot: CGFloat = iconButtonSize * 2 + 2
    static let sectionMaxHeight: CGFloat = 540
}

enum FleetColor {
    static var numeral: Color { SurfaceInk.numeral }
    static var surfaceWash: Color { SurfaceInk.surfaceWash }
    static var indicatorOn: Color { SurfaceInk.indicatorOn }
    static var indicatorOff: Color { SurfaceInk.indicatorOff }

    static var countPill: Color { Color.secondary.opacity(0.15) }
}

enum FleetAnimation {
    static let disclosure = Animation.easeOut(duration: 0.12)
}
