import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = emphasized ? .active : .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = emphasized ? .active : .followsWindowActiveState
    }
}

struct OpaqueLiquidGlassScene: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            ZStack {
                opaqueBase
                Rectangle()
                    .fill(.clear)
                    .glassEffect(
                        .regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.72)),
                        in: Rectangle()
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Color(nsColor: .windowBackgroundColor).opacity(0.90)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                content
            }
        } else {
            ZStack {
                opaqueBase
                VisualEffectBackground(
                    material: .underWindowBackground,
                    blendingMode: .withinWindow
                )
                Color(nsColor: .windowBackgroundColor).opacity(0.38)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                content
            }
        }
    }

    private var opaqueBase: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    func opaqueLiquidGlassScene() -> some View {
        modifier(OpaqueLiquidGlassScene())
    }
}

struct Hairline: View {
    var edge: VerticalEdge = .bottom
    var strong = false

    var body: some View {
        Rectangle()
            .fill(strong ? ConsoleColor.hairlineStrong : ConsoleColor.hairline)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func hairline(edge: VerticalEdge = .bottom, strong: Bool = false) -> some View {
        background(alignment: edge == .bottom ? .bottom : .top) {
            Hairline(edge: edge, strong: strong)
        }
    }
}

extension View {
    func elevatedCard(_ label: String? = nil,
                      padding: CGFloat = ConsoleMetrics.cardPadding) -> some View {
        plate(label, corner: ConsoleMetrics.cardCorner, padding: padding)
    }
}

struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    var cornerRadius: CGFloat = ConsoleMetrics.rowCorner

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(hovering ? SurfaceInk.hoverWash : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { hovering = $0 }
            .animation(ConsoleAnimation.selection, value: hovering)
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = ConsoleMetrics.rowCorner) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }
}

struct StatusPip: View {
    let tone: StatusTone
    var size: CGFloat = 8
    var pulsing = false

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        ZStack {
            if pulsing {
                Circle()
                    .strokeBorder(tone.edge, lineWidth: 1)
                    .frame(width: size * 1.6, height: size * 1.6)
            }
            if differentiateWithoutColor {
                Image(systemName: tone.verdict)
                    .font(.system(size: size * 1.6, weight: .bold))
                    .foregroundStyle(tone.ink)
            } else {
                Circle()
                    .fill(tone.color)
                    .frame(width: size, height: size)
                    .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
            }
        }
        .frame(width: size * 2.1, height: size * 2.1)

        .accessibilityHidden(true)
    }
}

struct ConsoleBadge: View {
    let text: String
    var tone: StatusTone = .neutral
    var symbol: String?
    var fillsCell = false

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .semibold))
            }
            Text(text)
                .font(ConsoleFont.badge)
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: fillsCell ? .infinity : nil,
               maxHeight: fillsCell ? .infinity : nil, alignment: .leading)
        .background(
            Capsule().fill(tone == .neutral
                           ? AnyShapeStyle(.quaternary)
                           : AnyShapeStyle(tone.chipFill))
        )
        .foregroundStyle(tone.ink)
    }
}

private struct LiveResizeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isLiveResizing: Bool {
        get { self[LiveResizeKey.self] }
        set { self[LiveResizeKey.self] = newValue }
    }
}
