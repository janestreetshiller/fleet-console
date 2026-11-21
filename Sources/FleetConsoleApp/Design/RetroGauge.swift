import SwiftUI

struct RetroGauge: View {
    let value: Double?
    let tone: StatusTone
    let caption: String
    let readout: String
    var diameter: CGFloat = ConsoleMetrics.gaugeDiameter

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private static let sweepStart: Double = 150
    private static let sweepDegrees: Double = 240

    private static let redlineStart: Double = 0.90

    private static let arcWidthRatio: CGFloat = 0.075
    private static let constructionInset: CGFloat = 0.09
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
            labels
        }
        .frame(width: diameter, height: diameter)
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(value == nil ? "not sampled yet" : readout)
    }

    private var face: some View {
        ZStack {
            Circle()
                .strokeBorder(ConsoleColor.hairline, lineWidth: SketchMetrics.hairline)
            Circle()
                .strokeBorder(ConsoleColor.hairlineStrong,
                              style: StrokeStyle(lineWidth: SketchMetrics.hairline,
                                                 dash: [2, 4]))
                .padding(diameter * Self.constructionInset)
        }
    }

    private var track: some View {
        GaugeArc(fraction: 1)
            .stroke(SurfaceInk.indicatorOff,
                    style: StrokeStyle(lineWidth: diameter * Self.arcWidthRatio, lineCap: .butt))
            .padding(diameter * 0.10)
    }

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

    private var needle: some View {
        NeedleShape()
            .fill(value == nil ? AnyShapeStyle(SurfaceInk.dim) : AnyShapeStyle(tone.color))
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(needleAngle))
    }

    private var hub: some View {
        Circle()
            .fill(SketchInk.plate)
            .overlay {
                Circle().strokeBorder(ConsoleColor.numeral, lineWidth: SketchMetrics.hairline)
            }
            .frame(width: diameter * Self.hubRatio, height: diameter * Self.hubRatio)
    }

    private var labels: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(readout)
                .font(ConsoleFont.mono(.caption, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(value == nil ? AnyShapeStyle(SurfaceInk.dim)
                                              : AnyShapeStyle(ConsoleColor.numeral))
                .offset(y: -diameter * 0.09)
            if differentiateWithoutColor && tone != .neutral && value != nil {
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
