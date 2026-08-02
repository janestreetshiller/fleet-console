import SwiftUI
import AppKit

// Window chrome primitives: vibrancy, hairlines, elevation, hover.
//
// These exist for the same reason `FleetRow` exists: the first version of the
// window reimplemented each effect inline, and inline effects drift. A surface
// asks for a named treatment; it never mixes its own shadows and borders.

// MARK: - Vibrancy

/// AppKit-backed material fill. SwiftUI's `Material` does not expose
/// `NSVisualEffectView`'s `behindWindow` blending state in every context, so
/// the one place that needs a guaranteed native backdrop (floating panels,
/// titlebar accessories) goes through the real thing.
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

// MARK: - Hairlines

/// A one-pixel surface edge, not a content separator. `Divider()` draws a
/// semantic separator with its own insets and appearance-dependent weight; a
/// hairline draws the boundary of a surface and nothing else.
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
    /// Draws a hairline along one edge of the view.
    func hairline(edge: VerticalEdge = .bottom, strong: Bool = false) -> some View {
        background(alignment: edge == .bottom ? .bottom : .top) {
            Hairline(edge: edge, strong: strong)
        }
    }
}

// MARK: - Elevation

/// The one elevated surface in the console: a card over the window background.
/// Fill, hairline and shadow are a single treatment — a card with a shadow but
/// no border, or a border but the wrong fill, is a different component that
/// does not exist here.
struct ElevatedCard: ViewModifier {
    var padding: CGFloat = ConsoleMetrics.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: ConsoleMetrics.cardCorner, style: .continuous)
                    .fill(ConsoleColor.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ConsoleMetrics.cardCorner, style: .continuous)
                    .strokeBorder(ConsoleColor.hairline, lineWidth: 1)
            )
            .shadow(color: ConsoleColor.cardShadow, radius: ConsoleMetrics.cardShadowRadius,
                    x: 0, y: ConsoleMetrics.cardShadowY)
    }
}

extension View {
    func elevatedCard(padding: CGFloat = ConsoleMetrics.cardPadding) -> some View {
        modifier(ElevatedCard(padding: padding))
    }
}

// MARK: - Hover

/// Uniform hover treatment for selectable surfaces in the content column:
/// a 6% fill, no scale, no colour shift on the content itself. macOS rows do
/// not grow or change weight on hover; they quietly acknowledge the pointer.
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

// MARK: - Status pip

/// The live connection/health dot. Shape carries meaning alongside colour
/// (HIG: never encode state in colour alone), and a gentle pulse marks the
/// *live* states — reachable nodes breathe once per two seconds, matching the
/// probe cadence that keeps them true. Reduced Motion turns the pulse off.
struct StatusPip: View {
    let tone: StatusTone
    var size: CGFloat = 8
    var pulsing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var breathing = false

    var body: some View {
        ZStack {
            if pulsing && !reduceMotion {
                Circle()
                    .fill(tone.edge)
                    .frame(width: size * 2.1, height: size * 2.1)
                    .scaleEffect(breathing ? 1 : 0.55)
                    .opacity(breathing ? 0 : 1)
            }
            if differentiateWithoutColor {
                // A lone pip has no text beside it, so with Differentiate Without
                // Colour on, a filled circle conveys nothing at all. The bare
                // verdict glyph is what separates here — enclosed status symbols
                // measure ~0.87 silhouette IoU against each other at this size,
                // bare ones 0.24. It draws at 1.6x the dot inside the halo's
                // existing 2.1x frame, so nothing reflows and nothing clips.
                Image(systemName: tone.verdict)
                    .font(.system(size: size * 1.6, weight: .bold))
                    .foregroundStyle(tone.ink)
            } else {
                // The dot keeps `color`, not `ink`, and that is deliberate: a
                // saturated indicator dot is the platform's own convention
                // (Control Center, Wi-Fi, recording indicators), and this one
                // carries its own contrast ring rather than relying on the hue
                // to separate it from the surface. Every *glyph* in the system
                // takes ink; this is the one fill that stays a fill.
                Circle()
                    .fill(tone.color)
                    .frame(width: size, height: size)
                    .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
            }
        }
        .frame(width: size * 2.1, height: size * 2.1)
        .onAppear {
            guard pulsing, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                breathing = true
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Badge

/// Small rounded count/latency badge used in the fleet sidebar and section
/// headers. Mono digits by default — badges here carry numbers, not words.
struct ConsoleBadge: View {
    let text: String
    var tone: StatusTone = .neutral
    var symbol: String?

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
        .background(
            Capsule().fill(tone == .neutral
                           ? AnyShapeStyle(.quaternary)
                           : AnyShapeStyle(tone.chipFill))
        )
        .foregroundStyle(tone.ink)
    }
}

// MARK: - Live resize

/// Whether a window-edge drag is in progress, as reported by AppKit.
///
/// Read by anything that animates a dimension derived from the window's width,
/// so that a drag moves the layout directly and a *discrete* change — a column
/// toggled, a map reordering because a process grew — still animates.
///
/// An environment value rather than a parameter because the views that need it
/// are not neighbours: the root's two side columns and every tile inside a
/// treemap four levels down. Threading a Bool through four initialisers to
/// reach `HeatmapView.tile` would put a window-management detail in the
/// signature of every view in between.
private struct LiveResizeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isLiveResizing: Bool {
        get { self[LiveResizeKey.self] }
        set { self[LiveResizeKey.self] = newValue }
    }
}
