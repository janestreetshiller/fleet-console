import SwiftUI
import AppKit

enum SketchMetrics {
    static let hairline: CGFloat = 1
    static let markStroke: CGFloat = 1.6
}

enum SketchInk {
    static var ground: Color { Color(nsColor: .windowBackgroundColor) }
    static var plate: Color { Color(nsColor: .controlBackgroundColor) }
    static var plateLabel: Color { Color(nsColor: .secondaryLabelColor) }
    static var accent: Color { FleetCorePalette.signal }
    static var accentAlt: Color { Color(nsColor: .systemPurple) }
    static var accentWarm: Color { Color(nsColor: .systemOrange) }
}

extension View {
    func sketchSubstrate(seed: Double = 0, grainSeed: UInt64 = 7,
                         ground: Bool = true) -> some View {
        modifier(NativeAccessibilityBehavior())
        .background {
            if ground {
                SketchInk.ground
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct NativeAccessibilityBehavior: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }
}

struct PlateSurface: ViewModifier {
    var corner: CGFloat
    var padding: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return content
            .padding(padding)
            .background { shape.fill(SketchInk.plate) }
            .overlay {
                shape.strokeBorder(Color(nsColor: contrast == .increased ? .labelColor : .separatorColor),
                                   lineWidth: contrast == .increased ? 1 : 0.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
    }
}

extension View {
    func plate(_ label: String? = nil,
               corner: CGFloat = ConsoleMetrics.cardCorner,
               padding: CGFloat = ConsoleMetrics.cardPadding) -> some View {
        modifier(PlateSurface(corner: corner, padding: padding))
    }
}

struct FleetMark: View {
    var size: CGFloat = 22
    var construction = true
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

            context.fill(
                Path(ellipseIn: CGRect(x: 7 * unit, y: 18 * unit, width: 3 * unit, height: 3 * unit)),
                with: .color(ink))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("FleetConsole")
    }
}
