import SwiftUI

// An analog dial for a bounded 0…1 metric — the instrument half of the Overview
// module, beside the traces that carry its history.
//
// Why an analog gauge at all, in an app that is otherwise flat and typographic:
// a needle is read as a *position on a fixed scale* without being decoded. A
// numeral has to be compared against a range you hold in your head ("is 77%
// memory bad?"); a needle sitting two ticks under the red band answers that
// before you have read the number. The five stacked cards this replaces each
// spent a full card header on a numeral that told you nothing without that
// context. So the dial is not nostalgia looking for a job — it is the densest
// honest encoding of "where in its range is this, right now", and the retro
// styling is what makes a dial legible as a dial at 92pt.
//
// Why it lives in Design/ rather than beside the module that uses it: this is
// where the design audit allows a hue and an opacity literal to be written down,
// because this is where they are *chosen* rather than typed next to whatever was
// already on screen. Every number below is named and argued for on that basis.
//
// What it inherits from the rest of FleetKit, unchanged:
//
//   * **Colour is a status vocabulary.** The bezel, face, ticks and readout plate
//     are achromatic in both appearances. The only hue on the dial is the tone,
//     and it appears in exactly two places — the value arc and the needle.
//   * **Nothing depends on colour alone.** The needle's angle carries the value,
//     the readout carries the number, and under Differentiate Without Colour the
//     tone's `verdict` glyph appears on the face.
//   * **No confident zero.** `value: nil` is a metric that has not been sampled
//     — the first tick after launch, a GPU that withheld its utilisation key —
//     and it parks the needle at the zero stop, drops the value arc entirely and
//     reads "—". A needle resting at zero and a needle resting at *no reading*
//     must not look the same, which is why the parked needle is dimmed and the
//     arc is absent rather than zero-length.

/// A 240° analog dial for a value in 0…1.
struct RetroGauge: View {
    /// 0…1, or nil when the metric has not been sampled yet.
    let value: Double?
    let tone: StatusTone
    /// The metric's name, on the face. Two or three characters: CPU, MEM, GPU.
    let caption: String
    /// The formatted current value, under the hub. Already includes its unit.
    let readout: String
    var diameter: CGFloat = ConsoleMetrics.gaugeDiameter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    // MARK: Geometry
    //
    // 240° with the gap at the bottom: the two dead quadrants are where the
    // readout goes, so the dial spends none of its diameter on chrome. A full
    // 360° ring has nowhere to put the number and no unambiguous zero.

    private static let sweepStart: Double = 150
    private static let sweepDegrees: Double = 240

    /// Where the redline starts, taken from the same thresholds the tones use
    /// rather than a number chosen to look right. A dial whose red band and whose
    /// needle colour disagree about "bad" is worse than a dial with no band.
    private static let redlineStart: Double = 0.90

    /// Ring widths as a share of the diameter, so a gauge at any size keeps its
    /// proportions. Solved at 92pt and then expressed as ratios.
    private static let arcWidthRatio: CGFloat = 0.075
    private static let bezelWidthRatio: CGFloat = 0.035
    private static let majorTickRatio: CGFloat = 0.085
    private static let minorTickRatio: CGFloat = 0.045
    private static let hubRatio: CGFloat = 0.14

    private var fraction: Double { min(1, max(0, value ?? 0)) }
    private var needleAngle: Double { Self.sweepStart + Self.sweepDegrees * fraction }

    var body: some View {
        ZStack {
            face
            Canvas { context, size in ticks(in: context, size: size) }
            track
            redline
            if value != nil { valueArc }
            needle
            hub
            glass
            labels
        }
        .frame(width: diameter, height: diameter)
        // Reduce Motion means the needle snaps between samples. The 2 s cadence
        // makes that a step every two seconds rather than a jitter, which is the
        // point: the animation is here to make the sweep readable, and someone
        // who has asked for less motion has asked for exactly the sweep to stop.
        .animation(reduceMotion ? nil : ConsoleAnimation.telemetry, value: fraction)
        .animation(reduceMotion ? nil : ConsoleAnimation.telemetry, value: value == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(value == nil ? "not sampled yet" : readout)
    }

    // MARK: Face and bezel

    /// The machined ring and the recessed face under it.
    ///
    /// Two gradients, both achromatic and both driven by `Color.primary` /
    /// `Color.white`, so the dial is lit from the top-left in light mode and
    /// stays a lifted panel in dark mode without a second hand-tuned palette.
    private var face: some View {
        ZStack {
            Circle()
                .fill(ConsoleColor.card)
            Circle()
                .fill(RadialGradient(colors: [Color.black.opacity(0.10), Color.clear],
                                     center: .center,
                                     startRadius: diameter * 0.10,
                                     endRadius: diameter * 0.50))
            Circle()
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.55),
                                                      Color.primary.opacity(0.18)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing),
                              lineWidth: diameter * Self.bezelWidthRatio)
            Circle()
                .strokeBorder(ConsoleColor.hairlineStrong, lineWidth: 0.5)
        }
    }

    /// The Aqua signature, kept to one soft ellipse over the top third. Any more
    /// and it stops being a lit instrument and starts being a plastic button.
    private var glass: some View {
        Ellipse()
            .fill(LinearGradient(colors: [Color.white.opacity(0.22), Color.clear],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: diameter * 0.62, height: diameter * 0.34)
            .offset(y: -diameter * 0.22)
            .allowsHitTesting(false)
    }

    // MARK: Scale

    private var track: some View {
        GaugeArc(fraction: 1)
            .stroke(SurfaceInk.indicatorOff,
                    style: StrokeStyle(lineWidth: diameter * Self.arcWidthRatio, lineCap: .butt))
            .padding(diameter * 0.10)
    }

    /// The redline band, drawn on the track rather than over the value: it is a
    /// property of the *scale*, so it has to be visible when the needle is
    /// nowhere near it. That is the whole reason to have one.
    private var redline: some View {
        GaugeArc(fraction: 1, from: Self.redlineStart)
            .stroke(StatusTone.bad.edge,
                    style: StrokeStyle(lineWidth: diameter * Self.arcWidthRatio, lineCap: .butt))
            .padding(diameter * 0.10)
    }

    private var valueArc: some View {
        GaugeArc(fraction: fraction)
            .stroke(tone.stroke,
                    style: StrokeStyle(lineWidth: diameter * Self.arcWidthRatio, lineCap: .butt))
            .padding(diameter * 0.10)
    }

    /// Nine major ticks — one every 30° — with four minors between each pair.
    /// Drawn in a single `Canvas` rather than as forty rotated `Rectangle`s: this
    /// view redraws on a 2 s cadence, and forty leaf views per gauge is a layout
    /// pass nobody sees the benefit of.
    private func ticks(in context: GraphicsContext, size: CGSize) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let outer = size.width / 2 - size.width * 0.09
        let majorInner = outer - size.width * Self.majorTickRatio
        let minorInner = outer - size.width * Self.minorTickRatio
        let steps = 40

        for step in 0...steps {
            let isMajor = step % 5 == 0
            let angle = Angle.degrees(Self.sweepStart + Self.sweepDegrees * Double(step) / Double(steps))
            let inner = isMajor ? majorInner : minorInner
            var path = Path()
            path.move(to: point(from: centre, radius: inner, angle: angle))
            path.addLine(to: point(from: centre, radius: outer, angle: angle))
            context.stroke(path,
                           with: .color(isMajor ? SurfaceInk.indicatorOn : SurfaceInk.indicatorOff),
                           lineWidth: isMajor ? 1.2 : 0.7)
        }
    }

    private func point(from centre: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(x: centre.x + radius * cos(angle.radians),
                y: centre.y + radius * sin(angle.radians))
    }

    // MARK: Needle

    /// A tapered needle with a short counterweight past the hub — the shape that
    /// makes the pivot read as a pivot rather than as a dot the line happens to
    /// start at.
    private var needle: some View {
        NeedleShape()
            .fill(value == nil ? AnyShapeStyle(SurfaceInk.dim) : AnyShapeStyle(tone.color))
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(needleAngle))
            .shadow(color: Color.black.opacity(0.25), radius: 1, y: 0.5)
    }

    private var hub: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color.primary.opacity(0.55),
                                              Color.primary.opacity(0.30)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
        }
        .frame(width: diameter * Self.hubRatio, height: diameter * Self.hubRatio)
    }

    // MARK: Legend

    /// The readout, and nothing else.
    ///
    /// The face used to carry the metric's name across its top, which was wrong
    /// twice over: the card header two points to the right already says "Memory",
    /// and at 92pt the word set inside the scale rather than under it — "MEMORY"
    /// crossed the arc it was supposed to sit inside. A dial in a titled card does
    /// not need to introduce itself. `caption` survives as the accessibility
    /// label, which is the one place the name is genuinely not already present.
    private var labels: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            // Under the hub, in the dial's dead sector. Monospaced digits for the
            // same reason every live number in this app is: a value that changes
            // every two seconds must not move the glyphs around it.
            Text(readout)
                .font(ConsoleFont.mono(.caption, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(value == nil ? AnyShapeStyle(SurfaceInk.dim)
                                              : AnyShapeStyle(ConsoleColor.numeral))
                .offset(y: -diameter * 0.09)
            if differentiateWithoutColor && tone != .neutral && value != nil {
                // The tone, as a shape, for anyone who cannot rely on the needle's
                // hue. Sits in the lower sector beside the readout rather than on
                // the scale, where it would be mistaken for a tick.
                Image(systemName: tone.verdict)
                    .font(ConsoleFont.badge)
                    .foregroundStyle(.secondary)
                    .offset(y: -diameter * 0.06)
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }
}

// MARK: - Shapes

/// The dial's arc, as an animatable shape. `fraction` is the animatable data, so
/// the value arc sweeps between samples instead of jumping — a `Canvas` capturing
/// a `Double` would redraw at the new value in one frame however it was animated.
private struct GaugeArc: Shape {
    var fraction: Double
    var from: Double = 0

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let start = 150.0 + 240.0 * min(1, max(0, from))
        let end = 150.0 + 240.0 * min(1, max(0, fraction))
        var path = Path()
        guard end > start else { return path }
        path.addArc(center: centre, radius: radius,
                    startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        return path
    }
}

/// The needle, drawn pointing along 0° (three o'clock) and rotated into place.
/// Tapered from the hub to a blunt tip: a needle that comes to a point loses its
/// last two pixels to antialiasing and reads as shorter than it is.
private struct NeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let length = min(rect.width, rect.height) * 0.36
        let tail = min(rect.width, rect.height) * 0.09
        let halfWidth = min(rect.width, rect.height) * 0.022
        let tipHalfWidth = halfWidth * 0.45

        var path = Path()
        path.move(to: CGPoint(x: centre.x - tail, y: centre.y - halfWidth * 0.7))
        path.addLine(to: CGPoint(x: centre.x + length, y: centre.y - tipHalfWidth))
        path.addLine(to: CGPoint(x: centre.x + length, y: centre.y + tipHalfWidth))
        path.addLine(to: CGPoint(x: centre.x - tail, y: centre.y + halfWidth * 0.7))
        path.closeSubpath()
        return path
    }
}
