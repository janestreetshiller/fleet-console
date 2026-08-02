import Foundation
import CoreGraphics

// The window's geometry, as arithmetic rather than as taste.
//
// Every fixed size in the console used to be an independent judgement call:
// 236 here, 268 there, 280 opposite, 320 beside it, 360 written as a bare
// literal inside a `private static let` that summed four of the others. Each was
// defensible on its own and none of them related to any of the rest, so the set
// could not be checked — and it turned out not to hold. `columnReserve` (what
// the three columns and the rail must keep) came to 786pt against a window whose
// minimum content width is `defaultContentSize.width / 2` = 780pt: at the
// narrowest size the user can drag to, the reserve exceeded the whole window and
// the module column fell under the floor its own comment sets. The comment
// beside it described a 1060pt minimum that has not existed for some time.
//
// The fix is not better numbers. It is deriving the numbers from two rules and
// then testing that the derivation holds at every size the window can take:
//
//   1. **The ladder.** Fixed sizes come from the Fibonacci sequence, so any two
//      of them are in a ratio the eye already reads as ordered, and adjacent
//      steps are far enough apart to be *decisions* rather than the 9pt/9.5pt
//      pair the design audit exists to prevent. The values already in the app
//      were closer to this than anyone had noticed — 236 vs 233, 88 vs 89, 20 vs
//      21, 12 vs 13 — which is the argument for snapping to the ladder rather
//      than inventing a scale: it is what the design was already reaching for.
//
//   2. **The golden section.** Anything that divides the *window* divides it at
//      φ. The content column was already 62.3% of the composed width, which is
//      1/φ to within half a point, so this too is a latent rule being written
//      down. The remainder — the minor section — is split equally between the
//      two side columns, which is what makes them mirror images.
//
// This lives in FleetCore rather than beside the view tokens for one reason:
// FleetCore is the target with tests. A layout budget nobody can assert is the
// state this file was written to leave.

public enum Scale {
    public static let phi: CGFloat = 1.618_033_988_749_895

    /// The ladder. Every fixed dimension in the console is one of these.
    ///
    /// Starts at 1 and stops at 987 because 1597 is wider than the window: a rung
    /// no layout can reach is a rung that invites rounding to it.
    public static let ladder: [CGFloat] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89,
                                           144, 233, 377, 610, 987]

    /// The nearest rung to an arbitrary measurement.
    ///
    /// For snapping a *derived* value — a golden-section division, a measured
    /// width — back onto the ladder, so a computed column and a declared one
    /// cannot land a point apart and read as a misalignment.
    public static func snap(_ value: CGFloat) -> CGFloat {
        guard let nearest = ladder.min(by: {
            abs($0 - value) < abs($1 - value)
        }) else { return value }
        return nearest
    }

    /// The major section of a length — the larger part when it is cut at φ.
    public static func major(_ total: CGFloat) -> CGFloat { total / phi }

    /// The minor section — what is left over, and the smaller part.
    public static func minor(_ total: CGFloat) -> CGFloat { total - major(total) }
}

/// The console window's column budget, and its one height.
///
/// It was all widths for as long as the window was aspect-locked: height
/// followed from width, so nothing had to lay out against it. The lock is gone
/// — dragging one edge moving the other is not how a Mac window behaves, and it
/// was most of what made resizing this one feel wrong — so height is now a free
/// dimension and needs a floor of its own, derived the same way the width's is.
public enum ConsoleLayout {

    // MARK: The rungs each part is pinned to

    /// Both side columns — the fleet mesh on the left and the inspector on the
    /// right — floor at the same rung, because they are the same thing pointing
    /// in opposite directions. The sidebar had 236 and the inspector 280, which
    /// is what made the window visibly lopsided at rest.
    public static let sideColumnMin: CGFloat = 233
    public static let sideColumnMax: CGFloat = 377

    /// The module column's floor. Was a bare `360` written inline in
    /// `ConsoleRootView`, where nothing could see it: below roughly this width
    /// the process table is more horizontal scrollbar than table.
    public static let moduleColumnMin: CGFloat = 377

    /// The chrome tool rail: one toggle with breathing room each side. Its two
    /// components are mirrored below and checked by the audit.
    public static let railWidth: CGFloat = toggleSize + railSpacing * 2

    /// The narrowest a tool panel can be and still draw its 40×10 floor: forty
    /// columns of an 8pt reference cell, plus SwiftTerm's 17pt scroller reserve
    /// and the 1pt drag edge, neither of which can draw a column.
    public static let panelMin: CGFloat = 40 * 8 + 17 + 1

    // MARK: Derived budgets

    /// The narrowest window that honours every floor at once *with a tool panel
    /// open*: one side column, the module column, the rail and the panel.
    ///
    /// This is the window's real minimum, and it is 982 — comfortably above the
    /// 780 the window has been advertising. At exactly this width, with a panel
    /// open, the inspector has yielded and the module column sits precisely on
    /// its floor, which is the definition of a budget that balances.
    public static let minimumContentWidth: CGFloat =
        sideColumnMin + moduleColumnMin + railWidth + panelMin

    /// The width below which the inspector yields to a tool panel: both side
    /// columns, the module column, the rail and the panel.
    public static let inspectorAndPanelFloor: CGFloat =
        sideColumnMin * 2 + moduleColumnMin + railWidth + panelMin

    /// The view layer's own values, restated here so the budget can be computed
    /// without importing it — the same arrangement `railWidth` uses.
    ///
    /// A mirror is a thing that drifts, so `Scripts/design-audit.sh` compares
    /// every name in this block against the `static let` of the same name in
    /// the view layer and fails if they disagree. That check is new, and it is
    /// here because `railWidth`'s own comment has claimed to be "asserted equal
    /// by test" since it was written and never was: `FleetCoreTests` cannot
    /// import the app target, so the assertion it named could not exist. A
    /// mirror guarded by a sentence is not guarded.
    public static let chartHeight: CGFloat = 89
    public static let cardPadding: CGFloat = 13
    public static let toggleSize: CGFloat = 22
    public static let railSpacing: CGFloat = 6

    /// A card's title row — one `subtitle` line — and the space under it.
    public static let cardTitleRow: CGFloat = 21
    public static let cardTitleGap: CGFloat = 8

    /// One telemetry card down to the bottom of its trace: padding, the title
    /// row, the gap under it, the chart, padding again. 144, which is a rung,
    /// and it lands there by arithmetic rather than by being typed.
    ///
    /// Deliberately *not* the tallest card. Overview's CPU card carries a core
    /// grid and a load line under its trace and comes to about 185; sizing the
    /// window's floor to the largest instrument any module might grow would make
    /// the floor a hostage to one card's contents. Down to the trace is the
    /// point past which the card stops being an instrument and starts being a
    /// cropped one; what hangs below it scrolls.
    public static let cardHeight: CGFloat =
        cardPadding * 2 + cardTitleRow + cardTitleGap + chartHeight

    /// What the unified-compact toolbar takes off the top.
    ///
    /// The window is `.fullSizeContentView`, so the content view runs under the
    /// title bar and this is content height that the module never sees. Leaving
    /// it out is what made the first version of the height floor wrong: the
    /// arithmetic was about the module column and the window handed the module
    /// column 55 points less than the arithmetic assumed, so the card the floor
    /// was defined to hold was cut off at the floor.
    public static let titlebarReserve: CGFloat = 55

    /// The module header — title, subtitle and the space under them.
    public static let moduleHeaderHeight: CGFloat = 55

    /// The module's bottom padding, below the last card.
    public static let moduleBottomPadding: CGFloat = 21

    /// The shortest window that still shows something honest: the toolbar, a
    /// module header, and one card down to the bottom of its trace.
    ///
    /// Derived rather than picked, because the last hand-picked window minimum
    /// in this file was wrong by six points and nobody could see it — the floor
    /// was "half the composed width", 780, against a column reserve of 786. A
    /// number nobody can check is a number that is eventually wrong.
    ///
    /// The first version of *this* number made the same mistake in miniature.
    /// It was `moduleHeaderHeight + cardHeight + 21` = 191, and rendering the
    /// window at exactly 191 showed the card sliced through the middle of its
    /// chart — because `.fullSizeContentView` puts the toolbar inside the
    /// content height and the arithmetic had not paid for it. The lesson is the
    /// one the file already teaches: a budget is worth what it is measured at.
    /// This one was measured, at 233, 246 and 288, before it was written down.
    ///
    /// Height was previously `minimumContentWidth / contentAspectRatio` — 567 —
    /// which was not a statement about content at all. It was the aspect lock
    /// talking.
    public static let minimumContentHeight: CGFloat =
        titlebarReserve + moduleHeaderHeight + cardHeight + moduleBottomPadding

    // MARK: The golden division

    /// The width one side column takes, given the width the split view has to
    /// divide (the window less the rail, and less a revealed panel).
    ///
    /// The content column takes the major section; the two side columns share
    /// the minor one, equally. Clamped to the ladder rungs above, so a window
    /// dragged narrow stops honouring the ratio before it stops honouring the
    /// floors — the ratio is what the layout *wants*, the floors are what it
    /// *needs*.
    public static func sideColumn(splitWidth: CGFloat) -> CGFloat {
        let ideal = Scale.minor(splitWidth) / 2
        return min(max(ideal, sideColumnMin), sideColumnMax)
    }

    /// What the module column is left with, for a given split width and how many
    /// side columns are showing. Nil when the arrangement does not fit, which is
    /// a question the caller has to be able to ask before it draws.
    public static func moduleColumn(splitWidth: CGFloat, sideColumns: Int) -> CGFloat? {
        let remaining = splitWidth - sideColumn(splitWidth: splitWidth) * CGFloat(sideColumns)
        return remaining >= moduleColumnMin ? remaining : nil
    }
}
