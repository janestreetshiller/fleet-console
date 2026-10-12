import SwiftUI

// FleetKit — the app's design tokens.
//
// Before this existed the views carried ~130 literal font sizes across twelve
// distinct values, including pairs that differ by half a point (9/9.5, 10/10.5,
// 12/12.5) for no reason anyone could reconstruct. A type ramp you can name is
// the difference between a design system and a pile of magic numbers.

// Sizes follow AppKit's own menu-bar extras (Wi-Fi, Control Center, Now Playing):
// 13pt primary, 11pt secondary, generous leading. The first draft ran 9–12.5pt,
// which is Xcode-inspector density, not menu density — technically legible and
// immediately readable as "not a Mac app".
enum FleetFont {
    /// Popover title.
    static let title = Font.system(size: 14, weight: .semibold)
    /// Primary text of a standard row — AppKit's menu item size.
    static let rowTitle = Font.system(size: 13)
    /// Primary text of a compact (fixed-height) row.
    static let rowTitleCompact = Font.system(size: 13)
    /// Body copy and table cells.
    static let body = Font.system(size: 13)
    /// Secondary line under a row title.
    static let subtitle = Font.system(size: 12)
    /// Timestamps, counts, hints.
    static let caption = Font.system(size: 12)
    /// Tags, badges, evidence chips.
    static let micro = Font.system(size: 11, weight: .medium)
    /// The smallest label in the system: stat-tile captions.
    static let nano = Font.system(size: 11)
    /// Disclosure chevron, used only by `DisclosureRow`.
    static let chevron = Font.system(size: 10, weight: .semibold)
    /// A glyph that annotates a row without becoming part of its text — the
    /// reply arrow on an answered agent message, and marks like it. The popover
    /// ramp's counterpart to `ConsoleFont.marker`.
    static let marker = Font.system(size: 8)
    /// The plotted legend struck into a plate's top border. The popover ramp's
    /// counterpart to `ConsoleFont.plateLabel`, one point smaller for the same
    /// reason every token here is: menu density, not window density.
    static let plateLabel = Font.system(size: 8, weight: .regular, design: .monospaced)
    /// Section labels — sentence case, secondary. Apple stopped shipping
    /// kerned all-caps headers in menus years ago.
    static let sectionLabel = Font.system(size: 12, weight: .semibold)
    /// Big numerals in stat tiles.
    static let stat = Font.system(size: 22, weight: .semibold)

    static func mono(_ size: CGFloat = 10, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum FleetMetrics {
    /// Horizontal inset for section content. AppKit menus use 14–16.
    static let gutter: CGFloat = 16
    /// Inset for rows, which sit inside a hover-highlight margin.
    static let rowInset: CGFloat = 10
    static let rowHighlightMargin: CGFloat = 6
    /// Gap between a row's icon and its text.
    static let rowGap: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 7
    /// Fixed height for compact rows.
    static let compactRowHeight: CGFloat = 36

    static let iconCompact: CGFloat = 26
    static let iconRow: CGFloat = 28
    static let iconRowLarge: CGFloat = 30
    /// Utilisation meters. Wide enough that 5% and 15% are distinguishable at a
    /// glance, narrow enough to sit in a row's accessory slot without pushing the
    /// subtitle into truncation.
    static let meterWidth: CGFloat = 54
    static let meterHeight: CGFloat = 5
    /// One column of the per-core grid.
    static let coreCellWidth: CGFloat = 7
    static let coreCellHeight: CGFloat = 22

    /// Menu highlights in AppKit are 5–6pt radius; tiles sit above them. Both
    /// track the console ramp in `ConsoleMetrics` — the two surfaces are
    /// different scales, not different shapes, so their corners stay in step.
    static let corner: CGFloat = 5
    static let tileCorner: CGFloat = 8
    /// Tags and micro capsules-with-corners.
    static let tagCorner: CGFloat = 3
    /// One column of the per-core grid, and any bar that narrow.
    static let barCorner: CGFloat = 2
    /// `EntityIcon`'s tile radius as a fraction of its size. Proportional so a
    /// 22pt row icon and a 38pt inspector icon are the same shape, and squarer
    /// than an app icon on purpose: this is a status tile, not an app.
    static let iconCornerRatio: CGFloat = 0.26
    /// The identity glyph inside an `EntityIcon` tile, as a fraction of the tile.
    static let iconGlyphRatio: CGFloat = 0.46
    /// The corner status badge, as a fraction of the tile it is anchored to.
    /// Large enough to carry a legible verdict glyph, small enough to stay
    /// inside the tile without an offset — see `EntityIcon`.
    static let iconBadgeRatio: CGFloat = 0.34
    /// The badge's contrast ring. Drawn with `strokeBorder`, so it insets rather
    /// than growing the badge past the tile edge.
    static let iconBadgeRing: CGFloat = 1.5
    /// Left inset of an expanded row's detail block, aligning it under the text.
    static let detailInset: CGFloat = 28
    /// Fixed column for a leading `StatusTone.verdict` glyph. The glyphs have
    /// different widths — a checkmark is wider than a minus — so stacked probe
    /// lines need a reserved column or their labels step in and out by a point.
    static let verdictColumn: CGFloat = 8
    static let popoverWidth: CGFloat = 480
    /// Natural-height tabs share a ceiling; long lists scroll within the body.
    static let popoverBodyHeight: CGFloat = 300
    /// One `IconButton`'s hit target. Named because three places need to agree
    /// on it: the button draws it, the action slot below is two of them wide,
    /// and the `ProgressView` that stands in for a refresh button has to occupy
    /// exactly the same room or the header twitches while a sweep runs.
    static let iconButtonSize: CGFloat = 28
    /// A trailing cluster of two icon buttons, reserved at a constant width
    /// whether or not both are on screen.
    ///
    /// The popover header holds it because a tab that puts up one button and a
    /// tab that puts up two would otherwise resize the segmented control you
    /// switch tabs with. A process row holds it for the same reason one step
    /// down: its two verbs appear on hover, and without the reservation the
    /// usage numeral — the column the list exists to be read down — slides
    /// 46pt left the moment the pointer lands on it, and a long process name
    /// truncates on hover and untruncates when you move away.
    static let actionSlot: CGFloat = iconButtonSize * 2 + 2
    /// The scroll clamp on a popover section's body — how tall State B is
    /// allowed to get before the section scrolls inside itself.
    ///
    /// One number, because the four sections share one popover: the picker
    /// above them and the footer below them are the same views whichever tab is
    /// selected, so a section that clamps higher than its neighbour drags the
    /// popover's bottom edge with it when you switch. It was written four times
    /// at two values — 540 on Services, Agents and Processes, 560 on
    /// Connections — which is the 9/9.5pt pair one layer up. Nobody chose 560;
    /// it was typed beside the section that happened to be longest, and that
    /// section is already the tallest of the four because it is the only one
    /// carrying an admin footer.
    static let sectionMaxHeight: CGFloat = 540
}

// MARK: - Color

/// The popover ramp's colour names.
///
/// Thin on purpose. Status colour is `StatusTone` and nothing else; the
/// achromatic inks are `SurfaceInk`, shared verbatim with the window ramp
/// because the ramp split is about type and metrics rather than about what a
/// colour means. What is left is the handful of popover-specific surfaces, named
/// here so no view has to write an opacity literal.
enum FleetColor {
    static var numeral: Color { SurfaceInk.numeral }
    static var surfaceWash: Color { SurfaceInk.surfaceWash }
    static var indicatorOn: Color { SurfaceInk.indicatorOn }
    static var indicatorOff: Color { SurfaceInk.indicatorOff }

    /// The pill behind a count in a section header — a shape whose job is to
    /// separate a numeral from the words either side of it, carrying no state.
    static var countPill: Color { Color.secondary.opacity(0.15) }
}

enum FleetAnimation {
    static let disclosure = Animation.easeOut(duration: 0.12)
}
