import SwiftUI
import AppKit

// Sketchfield — the substrate, and the plate that floats on it.
//
// This replaces Stampwork, and it replaces the argument Stampwork was making.
// Stampwork said *this is a printed page*: paper grain, a typewriter face, a
// mark struck like a rubber stamp. It was a treatment applied on top of a
// System-Settings window, and the two were arguing — a stamped header over a
// `controlBackgroundColor` card is a texture on a form, not a page.
//
// The release treatment is quiet and static: a faint spectral wash, native
// typography and concentric rectangular plates. No perpetual animation,
// full-window blur or per-pixel grain competes with the live measurements.
//
// What is deliberately *not* here: no new font. Stampwork vendored a display
// face and used it for four words; SF stays the reading face at every size the
// ramp already names, and the character comes from the drawing. What changes
// typographically is one token — `plateLabel` — and the rule that every
// measured value is monospaced, which the app was already half doing.
//
// Nothing in this file intercepts input: every decorative layer sets
// `allowsHitTesting(false)` and `accessibilityHidden(true)`.

// MARK: - Metrics

/// The treatment's own dimensions.
///
/// A third metrics home beside `FleetMetrics` (popover ramp) and
/// `ConsoleMetrics` (window ramp), for the same reason those two are separate:
/// these are not layout. A plate's second pass is 3pt down and right whether it
/// is a 380pt popover or a 233pt inspector card, because it is a property of
/// how the plate is *drawn*, not of the surface it is drawn on. Putting it in
/// either ramp would make it look like a spacing decision that a surface could
/// reasonably scale, and it is not one.
///
/// Every dimension here is a rung of the same Fibonacci ladder `ConsoleMetrics`
/// stands on. The strokes are not: a 1pt line and a 1.6pt line are two weights
/// of one mark, not two steps of a size hierarchy.
enum SketchMetrics {
    /// Inset of the concentric inner border.
    static let plateOffset: CGFloat = 3
    /// Graph-paper pitch. The same rung as `ConsoleMetrics.cardGap` and
    /// `sectionGap` — the ruling and the layout are on one grid or the grid is
    /// a lie.
    static let ruleFine: CGFloat = 13
    /// Every fifth line, drawn heavier. Derived rather than typed so the two
    /// cannot drift out of phase and turn the page into moiré.
    static let ruleHeavy: CGFloat = ruleFine * 5
    /// Where the plate label breaks the top border, from the leading edge.
    static let plateLabelInset: CGFloat = 13
    /// Air either side of the label inside the break.
    static let plateLabelPadding: CGFloat = 5
    /// How far the label rides above the border it interrupts — half its own
    /// line, so the border runs through the label's optical centre.
    static let plateLabelRise: CGFloat = 6
    /// Letter-tracking on a plate label. Wide, because a plotted label is read
    /// as a legend rather than as a word.
    static let plateLabelTracking: CGFloat = 1.4
    /// A field lobe's blur. Large enough that no lobe has an edge anywhere on
    /// screen — an edge would make it a shape, and it has to stay a wash.
    static let lobeBlur: CGFloat = 89
    /// A lobe's diameter as a share of the longest side of the surface it is
    /// drifting under, so the field is the same wash on a 380pt popover and a
    /// 1560pt window instead of three dots on the small one.
    ///
    /// 0.89 was the first value and it was wrong: at that span the three lobes
    /// are each wider than the window, so they overlap almost completely and
    /// the field resolves to one bruise on whichever side the darkest of them
    /// is anchored. Just over half the long side is what lets three lobes be
    /// three lobes.
    static let lobeSpan: CGFloat = 0.55
    /// How far a lobe travels over its cycle, as a share of its own diameter.
    static let lobeDrift: CGFloat = 0.13
    /// The field's strength when it is laid over a surface it does not own —
    /// the popover, which keeps `NSPopover`'s frame, arrow and material.
    static let fieldOverMaterial: Double = 0.55

    // Strokes. Below the ladder on purpose — see the note above.
    static let hairline: CGFloat = 1
    static let markStroke: CGFloat = 1.6
}


// MARK: - Ink

/// The substrate's colours.
///
/// Separate from `SurfaceInk`, which is the achromatic vocabulary every row and
/// chip shares and which stays derived from `Color.primary`. These are the four
/// decisions the restyle actually makes — what the page is, what a plate is,
/// what the field is made of, and the one accent that is not a status — and
/// each is a resolved pair rather than an opacity on a system colour, because a
/// window background that is `windowBackgroundColor` is the thing this pass
/// exists to stop being.
enum SketchInk {
    private static func pair(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    private static func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    /// The page. Near-black graphite in dark, cartridge paper — not white — in
    /// light: a sketchbook's ground is warm and a shade off, and a true white
    /// under a spectral field turns the field into a stain.
    static var ground: Color { pair(dark: rgba(7, 10, 13), light: rgba(242, 240, 234)) }

    /// A plate's own fill, over whatever the field is doing underneath. Carries
    /// its alpha deliberately: a plate is glass held over the page, and a plate
    /// you cannot see the field through is a card again.
    static var plate: Color { pair(dark: rgba(19, 24, 30, 0.96), light: rgba(255, 254, 251, 0.96)) }

    /// The second pass — the line the pen made coming back over its own edge.
    static var secondPass: Color { Color.primary.opacity(0.13) }

    /// A plate's label, struck into its top border.
    static var plateLabel: Color { Color.primary.opacity(0.55) }

    /// Graph-paper ruling: every line, and every fifth.
    static var ruleFine: Color { Color.primary.opacity(0.035) }
    static var ruleHeavy: Color { Color.primary.opacity(0.055) }

    /// The three lobes. Named by hue rather than by role because they have no
    /// role — the field means nothing, which is the only reason it is allowed
    /// to be the one saturated thing on screen that is not a status.
    static var fieldAqua: Color { pair(dark: rgba(34, 132, 140), light: rgba(169, 220, 214)) }
    static var fieldViolet: Color { pair(dark: rgba(90, 47, 122), light: rgba(203, 185, 232)) }
    static var fieldRose: Color { pair(dark: rgba(122, 58, 82), light: rgba(237, 196, 200)) }

    /// The accent. One hue, used for the mark, the live trace, a selected
    /// segment and a performance core — the things the eye is meant to find
    /// first and that carry no verdict. It is not a `StatusTone` and must never
    /// stand in for one.
    static var accent: Color { pair(dark: rgba(95, 227, 208), light: rgba(20, 138, 122)) }
    /// The accent's counterpart, for the second series in a two-series reading:
    /// efficiency cores against performance cores, write against read.
    static var accentAlt: Color { pair(dark: rgba(157, 139, 255), light: rgba(96, 76, 200)) }
    /// The warm third, for a series that is neither of the two above.
    static var accentWarm: Color { pair(dark: rgba(242, 184, 92), light: rgba(176, 112, 12)) }
}

// MARK: - The field

/// Static spectral wash. Radial gradients already have soft edges; expensive
/// blur, offscreen rasterization and continuous animation are unnecessary.
struct SketchField: View {
    /// Which arrangement this surface starts from. Two surfaces open at once —
    /// the popover over the window — and an identical field on both reads as a
    /// screenshot rather than as two pages.
    var seed: Double = 0


    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let span = max(size.width, size.height) * SketchMetrics.lobeSpan
            ZStack {
                lobe(SketchInk.fieldAqua, span: span, in: size,
                     at: UnitPoint(x: 0.10, y: 0.08))
                lobe(SketchInk.fieldViolet, span: span * 0.92, in: size,
                     at: UnitPoint(x: 0.88, y: 0.18))
                lobe(SketchInk.fieldRose, span: span * 1.08, in: size,
                     at: UnitPoint(x: 0.14, y: 0.92))
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One lobe, anchored in the surface's own coordinates.
    ///
    /// The anchor is a fraction of the *surface*, not of the lobe: the first
    /// version multiplied the anchor by the lobe's own span, so where a lobe sat
    /// depended on how big it was and every field piled up in the top-left
    /// corner of whatever it was drawn on.
    private func lobe(_ hue: Color, span: CGFloat, in size: CGSize,
                      at anchor: UnitPoint) -> some View {
        // The seed slides the whole arrangement along x, so two surfaces open at
        // once — the popover over the window — are not the same picture.
        let slide = CGFloat(seed.truncatingRemainder(dividingBy: 1) - 0.5) * 0.24
        return Circle()
            .fill(RadialGradient(colors: [hue, hue.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: span / 2))
            .frame(width: span, height: span)
            .position(x: (anchor.x + slide) * size.width, y: anchor.y * size.height)
    }
}

/// Graph paper: every 13pt, heavier every fifth.
struct GraphRuling: View {
    var body: some View {
        Canvas { context, size in
            var fine = Path()
            var heavy = Path()
            var x: CGFloat = 0
            var index = 0
            while x <= size.width {
                let line = Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) }
                if index % 5 == 0 { heavy.addPath(line) } else { fine.addPath(line) }
                x += SketchMetrics.ruleFine
                index += 1
            }
            var y: CGFloat = 0
            index = 0
            while y <= size.height {
                let line = Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) }
                if index % 5 == 0 { heavy.addPath(line) } else { fine.addPath(line) }
                y += SketchMetrics.ruleFine
                index += 1
            }
            context.stroke(fine, with: .color(SketchInk.ruleFine), lineWidth: SketchMetrics.hairline)
            context.stroke(heavy, with: .color(SketchInk.ruleHeavy), lineWidth: SketchMetrics.hairline)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The page's tooth. Kept verbatim from the Stampwork pass — a deterministic
/// seeded grain, drawn once per size and cached, at an opacity low enough that
/// text over it keeps full contrast. It was the one part of that treatment that
/// was making a surface feel like a surface rather than decorating one.
struct Grain: View {
    var seed: UInt64 = 0x5EED
    var opacity: Double = 0.035

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 3
            var state = seed &* 2862933555777941757 &+ 3037000493
            func next() -> Double {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
            }
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    if next() < 0.18 {
                        let grey = next()
                        let rect = CGRect(x: x, y: y, width: 1.2, height: 1.2)
                        context.fill(
                            Path(rect),
                            with: .color(Color(red: grey, green: grey, blue: grey)
                                .opacity(next() < 0.85 ? 1 : 0.5)))
                    }
                    x += step
                }
                y += step
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The whole substrate, in the order it is drawn: ground, field, ruling,
    /// tooth. Applied to a *window* or a *popover* — never to a card, which is
    /// a plate floating on this and has no substrate of its own.
    ///
    /// `ground: false` lays the field over whatever is already behind the view
    /// instead of painting the page first. That is the popover's form, and it
    /// is not a style choice: `NSPopover` draws its own frame and its own arrow
    /// in the system's popover material, and content that paints an opaque page
    /// inside it gives you a dark rectangle joined to a light arrow. The field,
    /// the ruling and the tooth are all translucent, so over the popover's own
    /// material they read as the same page without touching the frame the
    /// system owns.
    func sketchSubstrate(seed: Double = 0, grainSeed: UInt64 = 7,
                         ground: Bool = true) -> some View {
        background {
            ZStack {
                if ground { SketchInk.ground }
                // Held back where there is no page under it. The field is a
                // wash on a ground it can be part of; laid straight over the
                // system's popover material at full strength it is a stain on
                // someone else's surface.
                SketchField(seed: seed)
                    .opacity(ground ? 0.16 : 0.08)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - The plate

/// A rounded rectangle whose top border stops for the plate label and picks up
/// again on the other side of it.
///
/// The gap is measured from the label rather than assumed: a plate label is
/// `ConsoleFont.plateLabel` at a fixed size, but tracking and the label's own
/// characters decide its width, and a border that runs under two of its
/// letters is the detail that would make the whole treatment look accidental.
struct PlateBorder: Shape {
    var corner: CGFloat
    /// Width of the break in the top border. Zero draws a plain rounded rect.
    var gap: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = min(corner, min(rect.width, rect.height) / 2)
        var path = Path()

        let gapStart = rect.minX + SketchMetrics.plateLabelInset - SketchMetrics.plateLabelPadding
        let gapEnd = gapStart + gap
        let hasGap = gap > 0 && gapEnd < rect.maxX - r

        path.move(to: CGPoint(x: hasGap ? gapEnd : rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        if hasGap { path.addLine(to: CGPoint(x: gapStart, y: rect.minY)) }
        return path
    }
}

/// The second pass: the trailing and bottom edges only, drawn behind the plate
/// and offset, so what shows is the sliver the plate does not cover.
struct PlateSecondPass: Shape {
    var corner: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(corner, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY + r))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        return path
    }
}

private struct PlateLabelWidth: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Every card, panel and popover in the app.
///
/// One treatment, so a surface cannot have the border without the second pass
/// or the fill without the border — which is exactly how the old console ended
/// up with four row implementations. The label is optional because a nested
/// plate (a chip inside a card) is still a plate and would be absurd carrying a
/// legend of its own; the rule is that a plate labels itself only when it is
/// the thing a module is made of.
struct PlateSurface: ViewModifier {
    var label: String?
    var corner: CGFloat
    var padding: CGFloat

    @State private var labelWidth: CGFloat = 0

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return content
            .padding(padding)
            .background { shape.fill(SketchInk.plate) }
            .overlay {
                RoundedRectangle(cornerRadius: max(0, corner - SketchMetrics.plateOffset),
                                 style: .continuous)
                    .strokeBorder(SketchInk.secondPass.opacity(0.55), lineWidth: SketchMetrics.hairline)
                    .padding(SketchMetrics.plateOffset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay {
                PlateBorder(corner: corner, gap: label == nil ? 0 : labelWidth)
                    .stroke(ConsoleColor.hairlineStrong, lineWidth: SketchMetrics.hairline)
            }
            .overlay(alignment: .topLeading) {
                if let label {
                    PlateLabel(text: label)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: PlateLabelWidth.self,
                                                       value: geometry.size.width)
                            }
                        }
                        .offset(x: SketchMetrics.plateLabelInset - SketchMetrics.plateLabelPadding,
                                y: -SketchMetrics.plateLabelRise)
                }
            }
            .onPreferenceChange(PlateLabelWidth.self) { labelWidth = $0 }
    }
}

/// A plotted legend: monospaced, tracked, and never a sentence.
struct PlateLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(ConsoleFont.plateLabel)
            .tracking(SketchMetrics.plateLabelTracking)
            .foregroundStyle(SketchInk.plateLabel)
            .padding(.horizontal, SketchMetrics.plateLabelPadding)
            .fixedSize()
            .accessibilityHidden(true)
    }
}

extension View {
    /// The plate treatment. `label` is the plotted legend struck into the top
    /// border — a plate number and a three-letter name, never prose.
    func plate(_ label: String? = nil,
               corner: CGFloat = ConsoleMetrics.cardCorner,
               padding: CGFloat = ConsoleMetrics.cardPadding) -> some View {
        modifier(PlateSurface(label: label, corner: corner, padding: padding))
    }
}

// MARK: - The mark

/// The FleetConsole mark: one continuous stroke, the pen-down dot it started
/// from, and the construction circle it was struck against.
///
/// The outgoing mark was a bordered plate holding the letters "FC" in a
/// typewriter face, rotated two degrees to read as pressed. It was a stamp, and
/// a stamp is a thing you apply to a page rather than a thing you draw on one.
/// This is drawn: an F built from three strokes of a single path, sitting on the
/// circle a compass would have laid down first — the construction line left in,
/// which is the whole argument of the restyle in one 26pt glyph.
struct FleetMark: View {
    var size: CGFloat = 22
    /// Whether the construction circle is drawn. The menu bar gets the stroke
    /// alone: at 14pt in a bar full of system glyphs, the circle is the
    /// difference between a mark and a smudge.
    var construction = true

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let unit = s / 26

            if construction {
                let inset = SketchMetrics.markStroke * unit / 2
                context.stroke(
                    Path(ellipseIn: CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)),
                    with: .color(ConsoleColor.hairlineStrong),
                    lineWidth: SketchMetrics.hairline)
            }

            var stroke = Path()
            stroke.move(to: CGPoint(x: 8.5 * unit, y: 19.5 * unit))
            stroke.addLine(to: CGPoint(x: 8.5 * unit, y: 7 * unit))
            stroke.addLine(to: CGPoint(x: 18 * unit, y: 7 * unit))
            stroke.move(to: CGPoint(x: 8.5 * unit, y: 12.6 * unit))
            stroke.addLine(to: CGPoint(x: 15.2 * unit, y: 12.6 * unit))
            context.stroke(stroke, with: .color(SketchInk.accent),
                           style: StrokeStyle(lineWidth: SketchMetrics.markStroke * unit,
                                              lineCap: .round, lineJoin: .round))

            // The pen-down dot: where the stroke began, left visible.
            context.fill(
                Path(ellipseIn: CGRect(x: 7 * unit, y: 18 * unit, width: 3 * unit, height: 3 * unit)),
                with: .color(SketchInk.accent))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("FleetConsole")
    }
}
