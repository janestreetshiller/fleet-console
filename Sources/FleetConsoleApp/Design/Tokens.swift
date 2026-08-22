import SwiftUI
import FleetCore

// Console design tokens — the window-scaled half of FleetKit.
//
// `Theme.swift` carries the popover ramp (13pt rows, menu-bar density). The
// console window is a different surface with a different reading distance, so
// it gets its own ramp built on the dynamic type styles Apple reserves for
// window content (`title2`, `headline`, `subheadline`, `caption`). Nothing in
// the window should reach for a popover token, and vice versa.

// MARK: - Type

enum ConsoleFont {
    /// Module heading at the top of the content column.
    static let moduleTitle = Font.system(.title2, weight: .semibold)
    /// The welcome's one-line pitch. The only display-size text in the app,
    /// and it exists because a first-run window that types like a settings
    /// pane is a first-run window that says nothing.
    static let heroTitle = Font.system(.title, weight: .semibold)
    /// Card and group headings inside a module.
    static let cardTitle = Font.system(.headline, weight: .semibold)
    /// Primary row text in the content column.
    static let rowTitle = Font.system(.body)
    /// Card numerals beside a gauge — the same emphasis as the dial's own
    /// readout plate, in text form.
    static let cardValue = Font.system(.title3, weight: .semibold)
    /// Body copy in a card or a welcome paragraph.
    static let body = Font.system(.body)
    /// Secondary row text, evidence, hints.
    static let subtitle = Font.system(.subheadline)
    /// Timestamps, units, legend labels.
    static let caption = Font.system(.caption)
    /// Smaller than caption: the sensor metric's unit line.
    static let micro = Font.system(.caption2)
    /// Badge numerals and micro labels.
    static let badge = Font.system(.caption2, weight: .medium)
    /// A glyph that annotates a row without becoming part of its text — the
    /// supervised-by-the-controller shield, and anything else that sits after a
    /// title as a mark rather than a word.
    static let marker = Font.system(size: 9)
    /// The single large glyph over an empty panel. A dynamic `.title` rather than
    /// a fixed 22pt: it lands on the same size at the default text setting and,
    /// unlike the literal it replaces, grows when the user asks the system for
    /// larger text — which is the whole point of an empty state being legible.
    static let emptyGlyph = Font.system(.title)

    /// SF Mono for the things that *are* numbers: PIDs, ports, bytes, rates,
    /// addresses, load averages. Anything else in a technical row stays SF Pro.
    static func mono(_ style: Font.TextStyle = .callout, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }
}

// MARK: - Layout

// Every fixed size below is a rung of `Scale.ladder` — the Fibonacci sequence —
// and the column widths are `ConsoleLayout`'s golden division of the window.
// Neither is a new invention: the values that were here were already reaching
// for both and missing by a point or two (236 against 233, 88 against 89, 20
// against 21, 12 against 13), which is why snapping them changes almost nothing
// visually and changes everything about whether the set can be checked.
//
// `Tests/FleetCoreTests/ConsoleLayoutTests.swift` asserts the budget these feed.

enum ConsoleMetrics {
    /// Content-column gutter. Windows want more air than menus.
    static let gutter: CGFloat = 21
    static let cardPadding: CGFloat = 13
    /// Inset a panel's content from its own edges — the welcome's header and
    /// footer bars. Smaller than a card's interior, because a panel edge is
    /// already a boundary and needs less air than content inside it.
    static let panelInset: CGFloat = 8
    /// Corner ramp, one rung per level of nesting: card, then a row inside it,
    /// then a control inside that, then a bar, then a heatmap tile. Adjacent
    /// rungs are a φ ratio apart, which is what makes a highlighted row inside a
    /// card read as *nested* rather than as a second card — the relationship the
    /// old 10/7 pair was approximating.
    ///
    /// Tiles stay at the bottom rung because a treemap is read as contiguous
    /// area, and a visible corner gap breaks the reading.
    static let cardCorner: CGFloat = 8
    static let rowCorner: CGFloat = 5
    /// Chips and compact bordered buttons inside a card.
    static let controlCorner: CGFloat = 3
    /// Utilisation and storage bar segments.
    static let barCorner: CGFloat = 2
    /// One tile on a heatmap.
    static let mapTileCorner: CGFloat = 2
    /// The channel between neighbouring tiles — half of it taken off each side
    /// of a tile's computed rectangle. Replaces the hairline stroke that could
    /// not be seen on a saturated fill. One rung: below it the separation is not
    /// legible at a glance, above it the map starts reading as a grid of gaps
    /// rather than a partition of an area.
    static let mapTileGutter: CGFloat = 2
    /// Sidebar and inspector bounds.
    /// The toolbar's module picker. One number per segment, times
    /// `ConsoleModule.allCases.count`, so adding a module widens the picker
    /// instead of silently pushing the last segment past the slot's edge —
    /// which is how the sixth module shipped clipped down its middle.
    static let modulePickerSegment: CGFloat = 34
    static var modulePickerWidth: CGFloat {
        modulePickerSegment * CGFloat(ConsoleModule.allCases.count)
    }

    // MARK: The two side columns
    //
    // One set of numbers, used on both sides. The fleet mesh and the inspector
    // are the same column pointing in opposite directions — one names what you
    // are looking at, the other describes what you picked — and they had drifted
    // to 236/268/320 against 280/320/420, which is what made the window
    // measurably lopsided: 52pt more inspector than sidebar at rest.
    //
    // The floor is the longest thing either side actually has to hold: a device
    // name beside a latency badge, over a subtitle like "59% CPU · 67% RAM". At
    // 224 both lines elided, turning the one always-visible column into a column
    // of abbreviations. 233 clears it, and it is a rung.
    //
    // There is no separate *ideal*: the resting width is the golden section of
    // whatever the split view has to divide, computed per window size by
    // `ConsoleLayout.sideColumn(splitWidth:)`. A fixed ideal is what a ratio
    // replaces.

    static let sideColumnMin = ConsoleLayout.sideColumnMin
    static let sideColumnMax = ConsoleLayout.sideColumnMax

    /// Kept as the names the call sites use, both resolving to the same pair, so
    /// a future edit cannot make one side wider than the other by touching one
    /// of them. The mirroring is enforced here rather than remembered.
    static let sidebarMin = sideColumnMin
    static let sidebarMax = sideColumnMax
    static let inspectorMin = sideColumnMin
    static let inspectorMax = sideColumnMax

    /// Inspector header icon.
    static let iconInspector: CGFloat = 34
    /// The glyph in a table cell or a compact row — an app's own icon where the
    /// system has one, otherwise an SF Symbol at text weight. A rung, and the
    /// smallest at which a real application icon is still recognisable rather
    /// than a coloured smudge.
    static let iconRowGlyph: CGFloat = 13
    /// Live charts.
    static let chartHeight: CGFloat = 89
    static let chartHeightTall: CGFloat = 89
    /// Trace weight, and the inset that keeps it whole. A stroke centred on the
    /// plot boundary loses half its width to the edge, so the plot area is held
    /// off the frame by more than half a line — the trace is the content here,
    /// and a sheared trace reads as a rendering bug.
    /// Strokes sit below the ladder's floor deliberately: a 1pt line and a 2pt
    /// line are two weights of one mark, not two steps of a size hierarchy.
    static let chartStroke: CGFloat = 1.5
    static let chartPlotInset: CGFloat = 2
    /// Room held clear on the trailing edge for the two labels that state the y
    /// window. Without it the plot runs the full width and a trace that reaches
    /// its own upper bound — which auto-ranging guarantees it does — is drawn
    /// through the label naming that bound. 55 is the rung that clears the widest
    /// label these charts produce ("38.2 MB/s").
    static let chartAxisGutter: CGFloat = 55
    /// Below this a chart has no room for the two labels that state its y
    /// window, so it keeps its plain domain instead of auto-ranging. A zoomed
    /// axis nobody can read is worse than a flat one.
    static let chartAxisMinHeight: CGFloat = 55
    /// Analog gauges. 89pt is the smallest rung at which a 240° dial carries its
    /// nine ticks, a needle and a readout and still reads as an instrument
    /// rather than as a decorative ring: below it the tick pitch falls under a
    /// point and the minor ticks merge into a grey band. It is also the same
    /// rung as `chartHeight`, which is what makes a dial and the trace beside it
    /// the same height without either being told about the other.
    static let gaugeDiameter: CGFloat = 55
    /// The width a telemetry card needs before another fits beside it.
    ///
    /// **377 was wrong and made the module worse.** Snapping this up from 320
    /// during the ladder pass cut the Overview from three columns to two at the
    /// composed width, which is the opposite of the density the grid was added
    /// for: the cards got wider, the module got taller, and it went back to
    /// needing a scroll. A rung is only the right number if it is the right
    /// number.
    ///
    /// At 233 the content column fits three cards (3×233 + 2×13 = 725 inside
    /// 944) and each lands near 306pt — a 89pt dial and a 200pt trace, which is
    /// over three points per sample at sixty samples. Four would need 971 and
    /// does not fit, so this cannot silently become a chart nobody can read.
    static let cardMinWidth: CGFloat = 377
    /// Gap between cards in the module grid, in both axes.
    static let cardGap: CGFloat = 13
    /// Vertical rhythm between stacked cards in a scrolling module and between
    /// the welcome's zones. Same Fibonacci rung as `cardGap` — the gap is a
    /// gap whether it separates horizontally or vertically.
    static let sectionGap: CGFloat = 13
    /// The width a catalogue row needs before another fits beside it: icon, two
    /// lines of label, a right-aligned size and its button.
    ///
    /// 233 was tried, on the argument that four columns make the whole catalogue
    /// readable without scrolling. It does not give four — the module column is
    /// around 900pt, so it gives three — and the width it takes comes out of the
    /// name: nine of thirteen entries truncated to "Spotify offline ca…",
    /// "Hugging Face m…", "Xcode Derived…". A catalogue you cannot read the names
    /// in is not readable, whatever it costs in scrolling, and the module has the
    /// vertical room regardless: the bottom half of the window was empty while
    /// those names were being clipped.
    static let reclaimRowMinWidth: CGFloat = 377
    /// Heatmaps. A squarified map needs far more room than a trace — under
    /// ~250pt the fortieth tile stops being clickable. The disk map gets the
    /// taller one because it is its module's subject, not one card of five.
    static let mapHeight: CGFloat = 233
    static let mapHeightTall: CGFloat = 233
    /// The colour swatch in a legend chip or a hover readout: identity by
    /// colour only, with the label beside it.
    static let legendDot: CGFloat = 8
    /// The you-are-here marker in the process tree. Smaller than a swatch on
    /// purpose: it marks a row, it does not name a colour.
    static let treeMarker: CGFloat = 5
    /// The one shadow the app uses, so elevation cannot drift.
    static let cardShadowRadius: CGFloat = 8
    static let cardShadowY: CGFloat = 2
}

// MARK: - Color

enum ConsoleColor {
    /// Hairline borders — the replacement for `Divider()` wherever a surface
    /// edge, not a content separator, is being drawn. Chosen to survive both
    /// appearances without ever looking like a ruled line.
    static var hairline: Color { Color.primary.opacity(0.08) }
    static var hairlineStrong: Color { Color.primary.opacity(0.14) }

    /// Card fill over the window background. Uses the system's grouped-content
    /// background so light mode gets white cards on grey and dark mode gets
    /// lifted panels, exactly like System Settings.
    static var card: Color { Color(nsColor: .controlBackgroundColor) }
    /// The window background. Separate from `card` so the console can lift
    /// cards off it in both appearances without a second colour decision.
    static var window: Color { Color(nsColor: .windowBackgroundColor) }
    static var cardShadow: Color { Color.black.opacity(0.18) }

    /// Selected-row fill. The same value `RowBackground` uses in the popover
    /// ramp, named here so a selected row in the window cannot be a different
    /// strength of the same idea.
    static var selectionFill: Color { Color.accentColor.opacity(0.16) }

    // The achromatic inks are `SurfaceInk`, shared with the popover ramp. The
    // ramps differ in type and metrics, not in what a colour means — see the
    // note on `SurfaceInk` for why giving them separate values would be the
    // 9/9.5 font-size pair all over again.
    static var numeral: Color { SurfaceInk.numeral }
    static var surfaceWash: Color { SurfaceInk.surfaceWash }
    static var hoverWash: Color { SurfaceInk.hoverWash }
    static var selectedWash: Color { SurfaceInk.selectedWash }
    static var dim: Color { SurfaceInk.dim }
    static var outline: Color { SurfaceInk.outline }
    static var outlineStrong: Color { SurfaceInk.outlineStrong }
    static var indicatorOn: Color { SurfaceInk.indicatorOn }

    /// The dimmed remainder tile on a heatmap — the roll-up of everything too
    /// small to draw. Not a status and not a surface: it is the category's own
    /// colour, held back so the tile reads as *the rest* rather than as another
    /// entry competing with the ones that earned their area.
    static let remainderDim: Double = 0.35

    /// The tint for a destructive verb — Stop, Restart, Kill.
    ///
    /// Deliberately *not* `StatusTone.bad.color`, even though today they resolve
    /// to the same red. `StatusTone` answers "what is true about this service";
    /// this answers "what will this control do to it". A healthy service still
    /// gets a red Kill button, so routing the button through the status
    /// vocabulary would be a category error that happens to look right.
    static var destructive: Color { .red }

    // MARK: Ink on saturated fills
    //
    // The heatmap tiles are the one surface in the app whose background is a
    // saturated category or tone colour rather than a system material. That
    // breaks the usual rule: `Color.primary` flips with the *appearance*, but a
    // tile fill does not, so a primary-derived line goes black-on-red in light
    // mode and white-on-red in dark mode — one of which always loses. These
    // three are therefore deliberately fixed inks, chosen against the actual
    // `StorageCategory` and `StatusTone` fills rather than against the window.

    // `tileEdge` used to live here — a 0.18 black hairline, described as reading
    // "on the pale fills as well as the saturated ones". It did not: at 0.5pt
    // over a saturated fill it was invisible, which is why two adjacent tiles of
    // similar colour merged into one shape. Tiles are separated by a gutter now
    // (`ConsoleMetrics.mapTileGutter`), which is a layout decision rather than a
    // colour one and therefore cannot fail against a fill.

    /// Hover ring, drawn as two plies. White reads on every saturated fill;
    /// the dark ply just inside it is what carries the ring on the two pale
    /// greys, where white alone would vanish. One of the two always has
    /// contrast, in either appearance, on every fill the maps can produce.
    static var tileHoverRing: Color { Color.white.opacity(0.92) }
    static var tileHoverShade: Color { Color.black.opacity(0.35) }
}

/// The two throughput series, and the one place their colour and label live.
///
/// These were previously four literals in two files — `Color.teal` / `Color.orange`
/// on the `LineMark`s in `TelemetryCharts`, and `.teal` / `.orange` again on the
/// `LegendDot`s in `OverviewModule`. A legend is a claim about what a trace means,
/// so a legend that can drift from its trace by one careless edit is the exact
/// failure this toolbox exists to prevent. Naming the series makes the chart and
/// its key the same fact.
enum TelemetrySeries: String, CaseIterable, Identifiable {
    case read, write

    var id: String { rawValue }
    var label: String { rawValue }

    var color: Color {
        switch self {
        case .read: return .teal
        case .write: return .orange
        }
    }
}

/// The APFS storage vocabulary. One colour per category, in the order the
/// segmented bar draws them, matched to what About This Mac → Storage uses so
/// the bar reads as a Mac native rather than as a dashboard widget.
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

    /// In-tile label colour on this category's fill. The fills are saturated
    /// system colours; one global label colour fails contrast on at least two
    /// of them in each appearance, so the choice is per category and static.
    var tileLabelColor: Color {
        switch self {
        case .apps, .developer, .media, .other: return .white
        default: return .black
        }
    }
}

// MARK: - Motion

enum ConsoleAnimation {
    /// Live telemetry easing: fast enough to feel alive, slow enough that a
    /// 2 s sample cadence does not strobe.
    static let telemetry = Animation.easeOut(duration: 0.35)
    /// Selection and disclosure motion in the window.
    static let selection = Animation.easeOut(duration: 0.15)
    /// Storage bar segment growth after a scan completes.
    static let barGrowth = Animation.spring(response: 0.5, dampingFraction: 0.8)

    /// A side column opening or closing.
    ///
    /// Both sides take this one value, which is the whole of what makes the
    /// butterfly read as a butterfly: two panels on the same easing look like
    /// one gesture, and two panels a hundred milliseconds apart look like a bug.
    /// Critically damped — a column that overshoots its width and settles back
    /// reads as the layout being unsure, and this one is carrying a table.
    static let column = Animation.spring(response: 0.34, dampingFraction: 1)

    /// A treemap relaying out: tiles moving to new rectangles as the data
    /// changes or the panel is resized.
    ///
    /// Slower than `selection` and slower than a column, deliberately. A
    /// squarified layout can reorder tiles wholesale when one process grows, and
    /// at 0.15s that is a flicker rather than a movement you can follow — the
    /// point of animating it at all is that you can see *this tile became that
    /// tile* instead of the map simply being different.
    static let mapLayout = Animation.spring(response: 0.55, dampingFraction: 0.9)
}

/// One-off, non-repeating motion. The welcome's entrance and its gauge sweep
/// are the two places the app moves *at* you rather than with you, and they
/// are named here so a third one-off cannot quietly invent its own timing.
enum ConsoleMotion {
    /// Short fade-and-rise for content appearing on a stage.
    static let micro = Animation.easeOut(duration: 0.6)
    /// The welcome gauge's 0 → 78% → 12% spin-up. 3.2 s is long enough to
    /// read as a demonstration and short enough that the Skip button is never
    /// impatient.
    static let welcomeSweep = Animation.easeInOut(duration: 3.2)
    /// The welcome window's entrance as a whole — the panel fading in while
    /// the gauge sweeps. Slightly quicker than the sweep so the stage is
    /// present before the demonstration is over.
    static let welcomeEntrance = Animation.easeOut(duration: 0.45)
}
