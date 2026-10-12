import SwiftUI
import AppKit

// Shared native surfaces and the FleetConsole mark.
enum SketchMetrics {
    static let hairline: CGFloat = 1
    static let markStroke: CGFloat = 1.6
}

enum SketchInk {
    static var ground: Color { Color(nsColor: .windowBackgroundColor) }
    static var plate: Color { Color(nsColor: .controlBackgroundColor) }
    static var plateLabel: Color { Color(nsColor: .secondaryLabelColor) }
    static var accent: Color { .accentColor }
    static var accentAlt: Color { Color(nsColor: .systemPurple) }
    static var accentWarm: Color { Color(nsColor: .systemOrange) }
}

extension View {
    // Retains the existing surface API; AppKit supplies the appearance colors.
    func sketchSubstrate(seed: Double = 0, grainSeed: UInt64 = 7,
                         ground: Bool = true) -> some View {
        background {
            if ground {
                SketchInk.ground
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct PlateSurface: ViewModifier {
    var corner: CGFloat
    var padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return content
            .padding(padding)
            .background { shape.fill(SketchInk.plate) }
            .overlay {
                shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
    }
}

extension View {
    // Labels belong in the content hierarchy rather than a tiny border legend.
    func plate(_ label: String? = nil,
               corner: CGFloat = ConsoleMetrics.cardCorner,
               padding: CGFloat = ConsoleMetrics.cardPadding) -> some View {
        modifier(PlateSurface(corner: corner, padding: padding))
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
    /// The stroke's ink. White on the app badge's dark plate, the sketch accent
    /// on the paper.
    var ink: Color = SketchInk.accent

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
            context.stroke(stroke, with: .color(ink),
                           style: StrokeStyle(lineWidth: SketchMetrics.markStroke * unit,
                                              lineCap: .round, lineJoin: .round))

            // The pen-down dot: where the stroke began, left visible.
            context.fill(
                Path(ellipseIn: CGRect(x: 7 * unit, y: 18 * unit, width: 3 * unit, height: 3 * unit)),
                with: .color(ink))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("FleetConsole")
    }
}
