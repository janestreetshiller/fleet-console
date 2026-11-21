import SwiftUI
import FleetCore

enum ConsoleFont {
    static let moduleTitle = Font.system(.title2, weight: .semibold)
    static let heroTitle = Font.system(.title, weight: .semibold)
    static let cardTitle = Font.system(.headline, weight: .semibold)
    static let rowTitle = Font.system(.body)
    static let cardValue = Font.system(.title3, weight: .semibold)
    static let metricValue = Font.system(.largeTitle, weight: .semibold)
    static let body = Font.system(.body)
    static let subtitle = Font.system(.subheadline)
    static let caption = Font.system(.callout)
    static let micro = Font.system(.footnote)
    static let badge = Font.system(.footnote, weight: .medium)
    static let marker = Font.system(size: 9)

    static let plateLabel = Font.system(size: 9, weight: .regular, design: .monospaced)
    static let emptyGlyph = Font.system(.title)

    static func mono(_ style: Font.TextStyle = .callout, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }
}

enum ConsoleMetrics {
    static let gutter: CGFloat = 21
    static let cardPadding: CGFloat = 13
    static let gridQuantum: CGFloat = 8
    static let popoverMetricMinWidth: CGFloat = 89
    static let interpreterPresetMaxHeight: CGFloat = 233
    static let panelInset: CGFloat = 8
    static let workRowHeight: CGFloat = 34
    static let cardCorner: CGFloat = 8
    static let rowCorner: CGFloat = 5
    static let controlCorner: CGFloat = 3
    static let barCorner: CGFloat = 2
    static let mapTileCorner: CGFloat = 2
    static let mapTileGutter: CGFloat = 2
    static let modulePickerSegment: CGFloat = 34
    static var modulePickerWidth: CGFloat {
        modulePickerSegment * CGFloat(ConsoleModule.allCases.count)
    }
    static let processViewPickerWidth: CGFloat = 377

    static let sideColumnMin = ConsoleLayout.sideColumnMin
    static let sideColumnMax = ConsoleLayout.sideColumnMax

    static let sidebarMin = sideColumnMin
    static let sidebarMax = sideColumnMax
    static let inspectorMin = sideColumnMin
    static let inspectorMax = sideColumnMax

    static let iconInspector: CGFloat = 34
    static let iconRowGlyph: CGFloat = 13
    static let chartHeight: CGFloat = 89
    static let chartPrimaryHeight: CGFloat = 233
    static let chartFocusHeight: CGFloat = 377
    static let chartSecondaryHeight: CGFloat = 144
    static let chartStroke: CGFloat = 1.5
    static let chartPlotInset: CGFloat = 2
    static let chartAxisGutter: CGFloat = 55
    static let chartAxisMinHeight: CGFloat = 55
    static let gaugeDiameter: CGFloat = 55
    static let cardMinWidth: CGFloat = 377
    static let cardGap: CGFloat = 13
    static let sectionGap: CGFloat = 13
    static let reclaimRowMinWidth: CGFloat = 377
    static let mapHeight: CGFloat = 233
    static let legendDot: CGFloat = 8
    static let treeMarker: CGFloat = 5
}

enum ConsoleColor {
    static var hairline: Color { Color.primary.opacity(0.08) }
    static var hairlineStrong: Color { Color.primary.opacity(0.14) }

    static var card: Color { SketchInk.plate }
    static var window: Color { SketchInk.ground }

    static var selectionFill: Color { SketchInk.accent.opacity(0.16) }

    static var numeral: Color { SurfaceInk.numeral }
    static var surfaceWash: Color { SurfaceInk.surfaceWash }
    static var hoverWash: Color { SurfaceInk.hoverWash }
    static var selectedWash: Color { SurfaceInk.selectedWash }
    static var dim: Color { SurfaceInk.dim }
    static var outline: Color { SurfaceInk.outline }
    static var outlineStrong: Color { SurfaceInk.outlineStrong }
    static var indicatorOn: Color { SurfaceInk.indicatorOn }

    static let remainderDim: Double = 0.35

    static var destructive: Color { .red }

    static var tileHoverRing: Color { Color.white.opacity(0.92) }
    static var tileHoverShade: Color { Color.black.opacity(0.35) }
}

enum TelemetrySeries: String, CaseIterable, Identifiable {
    case read, write

    var id: String { rawValue }
    var label: String { rawValue }

    var color: Color {
        switch self {
        case .read: return SketchInk.accent
        case .write: return SketchInk.accentWarm
        }
    }
}

enum StorageCategory: String, CaseIterable, Identifiable {
    case apps = "Apps"
    case developer = "Developer"
    case caches = "Caches"
    case documents = "Documents"
    case downloads = "Downloads"
    case media = "Media"
    case other = "System & Other"
    case purgeable = "Purgeable"
    case free = "Free"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .apps: return .blue
        case .developer: return .purple
        case .caches: return .orange
        case .documents: return .teal
        case .downloads: return .mint
        case .media: return .pink
        case .other: return Color(nsColor: .systemGray)
        case .purgeable: return Color(nsColor: .systemGray).opacity(0.45)
        case .free: return Color(nsColor: .quaternaryLabelColor).opacity(0.35)
        }
    }

    var symbol: String {
        switch self {
        case .apps: return "app.fill"
        case .developer: return "hammer.fill"
        case .caches: return "shippingbox.fill"
        case .documents: return "doc.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .media: return "play.rectangle.fill"
        case .other: return "externaldrive.fill"
        case .purgeable: return "gobackward"
        case .free: return "circle.dashed"
        }
    }

    var tileLabelColor: Color {
        switch self {
        case .apps, .developer, .media, .other: return .white
        default: return .black
        }
    }
}

enum ConsoleAnimation {
    static let telemetry = Animation.easeOut(duration: 0.35)
    static let selection = Animation.easeOut(duration: 0.15)
    static let barGrowth = Animation.spring(response: 0.5, dampingFraction: 0.8)

    static let column = Animation.spring(response: 0.34, dampingFraction: 1)

    static let mapLayout = Animation.spring(response: 0.55, dampingFraction: 0.9)
}

enum ConsoleMotion {
    static let welcomeSweep = Animation.easeInOut(duration: 3.2)
    static let welcomeEntrance = Animation.easeOut(duration: 0.45)
}
