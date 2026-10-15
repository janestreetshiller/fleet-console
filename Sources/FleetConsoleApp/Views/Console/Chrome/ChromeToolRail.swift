import SwiftUI
import AppKit
import FleetCore

// The chrome rail and its spring-loaded panel — the host side of the seam
// declared in `ToolSurface.swift`.
//
// Everything here is laid out as *reserved space*, never as an overlay. The
// window's top ribbon (the module picker, the fleet device label, the search
// field, the refresh button and the controller pill) lives in the titlebar
// strip, which is AppKit's NSToolbar plus a titlebar accessory; this rail lives
// in the window's content view, attached with `safeAreaInset(edge: .trailing)`.
// Two independent facts keep it off the ribbon's words:
//
//   1. `safeAreaInset` *subtracts* width from the split view rather than
//      floating over it, so the rail and the panel take their room out of the
//      layout at every window width — there is no ZStack and no `.overlay`
//      anywhere in this file.
//   2. The inset content is laid out inside the container's safe area, whose
//      top inset is the titlebar+toolbar strip of a `.fullSizeContentView`
//      window. Even if the two frames did meet, AppKit composites the titlebar
//      container above the content view, so content cannot draw over toolbar
//      text.
//
// Because the rail is reserved rather than floating, the ribbon's own content
// is the thing that has to give — which is why the module header, the fleet
// label and the controller pill all truncate with a tail ellipsis.

// MARK: - Rail metrics

/// Derived from `ConsoleToolMetrics` and `ConsoleMetrics` rather than measured
/// by eye. Kept local for the same reason `ConsoleToolMetrics` is: the chrome
/// work should land without touching the token file. Fold both in afterwards.
enum ChromeRailMetrics {
    /// One toggle wide, with the rail's own spacing as its side padding.
    static let railWidth = ConsoleToolMetrics.toggleSize + ConsoleToolMetrics.railSpacing * 2

    /// The panel's drag edge, as drawn — a hairline, like every other divider
    /// in the window.
    static let handleWidth: CGFloat = 1

    /// The edge's *hit* region, which is a different number and has to be.
    /// AppKit's own split dividers draw a hairline and accept the pointer for
    /// about ten points around it; this drew five and accepted five, which is
    /// under half the target macOS trains people to expect and is why the panel
    /// could not be dragged in practice.
    static let handleHitWidth: CGFloat = 10

    /// What the three columns must keep no matter how wide the panel is asked
    /// to be.
    ///
    /// This used to sum its own four numbers, and the sum was wrong in a way
    /// nothing could see: 786pt of reserve against a window whose minimum
    /// content width was 780. `ConsoleLayout` owns the budget now and
    /// `ConsoleLayoutTests` proves it balances at both the minimum and the
    /// composed size, so this is one subtraction from a checked total rather
    /// than a fifth independent opinion about how wide a column should be.
    static let columnReserve = ConsoleLayout.inspectorAndPanelFloor
        - ConsoleLayout.panelMin
}

// MARK: - State

/// Owns the three surfaces, which one is revealed, and the geometry discipline
/// between the panel's pixels and a child process's columns.
///
/// Lives on the window controller, not in a view: the surfaces hold child
/// processes, and a terminal must not be torn down because SwiftUI rebuilt a
/// struct.
@Observable
@MainActor
final class ChromeTools {
    let registry = ToolSurfaceRegistry()

    private(set) var revealed: ConsoleTool?

    /// Only ever written from a coalescer callback, never from a layout pass —
    /// which is also why the "too narrow" state is derived from it rather than
    /// from the raw proposed size.
    private(set) var settledGrid: TerminalGrid?

    /// What the operator dragged the panel to. Clamped at render against the
    /// window's actual width; stored unclamped so widening the window restores
    /// the width they chose.
    var requestedPanelWidth = ConsoleToolMetrics.panelIdeal

    private(set) var context = ToolContext()

    @ObservationIgnored private var coalescers: [ConsoleTool: ToolResizeCoalescer] = [:]

    /// The panel's last measured content size, kept so `regrid()` can recompute
    /// against a re-measured cell without waiting for the panel to move.
    @ObservationIgnored private var lastProposedSize: CGSize = .zero

    // MARK: Reveal

    /// One implementation for all three toggles. The only per-tool branch in the
    /// whole rail is `ToolSurfaceRegistry.surface(for:)`, which is where it
    /// belongs.
    func toggle(_ tool: ConsoleTool, context: ToolContext) {
        if revealed == tool {
            dismiss()
            return
        }
        // Switching tools tears the outgoing panel down through the same path a
        // dismissal takes, so a tool cannot be left half-revealed.
        if revealed != nil { dismiss() }
        self.context = context
        settledGrid = nil
        revealed = tool
        registry.surface(for: tool).activate(context: context)
    }

    /// Opens the terminal on `context` and runs `commandLine` in it. The way an
    /// outside agent is started from inside the app: in a shell you can watch,
    /// answer and stop, not as a hidden child.
    @discardableResult
    func run(_ commandLine: String, in context: ToolContext) -> Bool {
        if revealed == .terminal { update(context: context) } else { toggle(.terminal, context: context) }
        return (registry.surface(for: .terminal) as? TerminalPanel)?.run(commandLine) ?? false
    }

    func investigate(_ starter: String, executable: URL, subject: String) -> Bool {
        guard let terminal = registry.surface(for: .terminal) as? TerminalPanel,
              terminal.investigate(starter, executable: executable) else { return false }
        let context = ToolContext(subject: "Investigate · " + subject)
        if revealed == .terminal { update(context: context) } else { toggle(.terminal, context: context) }
        return true
    }

    func dismiss() {
        guard let tool = revealed else { return }
        coalescers[tool]?.reset()
        registry.surface(for: tool).deactivate()
        revealed = nil
        settledGrid = nil
    }

    /// Re-open the live panel against a new selection. Cheap when nothing moved,
    /// because `ToolContext` is `Equatable`.
    func update(context: ToolContext) {
        guard self.context != context else { return }
        self.context = context
        guard let tool = revealed else { return }
        registry.surface(for: tool).activate(context: context)
    }

    // MARK: Geometry

    /// Called as often as the layout system likes. Nothing reaches a child
    /// process from here — the coalescer decides when a size has stopped moving.
    func propose(size: CGSize) {
        lastProposedSize = size
        regrid()
    }

    /// Re-derive the grid from the last measured panel size.
    ///
    /// Split out from `propose(size:)` because the grid is a function of two
    /// things, and only one of them is the panel: moving the window to a display
    /// with a different backing scale re-measures the character cell without the
    /// panel changing size by a single point, and the grid has to follow.
    func regrid() {
        guard let tool = revealed, tool.isPTYBacked,
              lastProposedSize.width > 0, lastProposedSize.height > 0 else { return }
        // The surface owns the font, so it owns the cell. This measured against
        // `TerminalCellMetrics.placeholder` — a 7×15 stand-in — while the panel
        // was drawing an 8×16 cell (JetBrains Mono NFM at 12pt) and reserving a
        // further 17pt for the scroller it never subtracted. At the default
        // 420pt panel that asked a child for 59×40 and then laid it out at
        // 489×640 inside a 415×600 hole, and `PTYHostView` clipped the
        // difference: nine of Yazi's columns sliced off the trailing edge, and
        // two and a half rows of the shell — the ones a fresh prompt is printed
        // on — pushed off the top. The same panel now settles 49×37.
        //
        // The placeholder stays as the answer for a surface that has not
        // published a cell yet, which is the only thing it was ever good for.
        let surface = registry.surface(for: tool) as? any PTYBackedSurface
        let cell = surface?.cellMetrics ?? .placeholder
        let reserved = surface?.reservedWidth ?? 0
        coalescer(for: tool).propose(
            TerminalGrid.fitting(lastProposedSize, cell: cell, reservedWidth: reserved))
    }

    /// The end of a drag, or a panel that has just been revealed and should not
    /// wait out the quiet period before its first paint.
    func flushGeometry() {
        guard let tool = revealed, tool.isPTYBacked else { return }
        coalescers[tool]?.flush()
    }

    private func coalescer(for tool: ConsoleTool) -> ToolResizeCoalescer {
        if let existing = coalescers[tool] { return existing }
        let made = ToolResizeCoalescer { [weak self] grid in
            guard let self else { return }
            self.settledGrid = grid
            self.registry.surface(for: tool).resize(to: grid)
        }
        coalescers[tool] = made
        return made
    }

    /// The panel's actual width: what was asked for, bounded by the seam's
    /// limits, and bounded again by what the three columns can spare. At the
    /// window's 1060pt minimum this yields 346pt — above `panelMin`, so the
    /// panel never has to squeeze a column below its floor to exist.
    func panelWidth(outerWidth: CGFloat) -> CGFloat {
        let spare = outerWidth - ChromeRailMetrics.columnReserve
        let ceiling = min(ConsoleToolMetrics.panelMax, max(ConsoleToolMetrics.panelMin, spare))
        return min(max(ConsoleToolMetrics.panelMin, requestedPanelWidth), ceiling)
    }

    /// True when the settled grid cannot honestly draw a full-screen TUI. Only
    /// PTY-backed tools ever settle a grid.
    var isTooNarrow: Bool {
        guard let grid = settledGrid else { return false }
        return !grid.fitsMinimum
    }
}

// MARK: - The reserved field

/// Rail plus panel, as one trailing inset. The rail is always present so the
/// space it occupies never changes; only the panel's width comes and goes.
struct ChromeToolField: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel
    let tools: ChromeTools

    /// The window's full content width, measured behind the inset. Needed to
    /// clamp the panel; read from a background rather than from the panel itself
    /// so the clamp cannot depend on its own result.
    let outerWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if let tool = tools.revealed {
                ChromeToolPanel(tool: tool, tools: tools,
                                width: tools.panelWidth(outerWidth: outerWidth))
            }
        }
        // No transition and no spring.
        //
        // This carried `.transition(.move(edge: .trailing))` under a comment
        // explaining that the panel slides in. It never did: a move transition
        // needs a container whose frame is stable across the change, and this
        // one inserts a view into an `HStack` whose width changes on the same
        // frame, so SwiftUI fell back to its default opacity fade. The result
        // was a panel that dissolved into place — motion that belongs to a
        // popover, on a thing that is a column.
        //
        // The panel is a screen in a fixed frame. It is either showing or it is
        // not, and switching tools swaps what is on it. Appearing immediately is
        // what that reads as, and it also means a PTY-backed surface is handed
        // exactly one grid instead of one per frame of a spring.
    }
}

// MARK: - The rail

/// The reserved strip of chrome: home, then one toggle per `ConsoleTool`.
private struct ChromeRail: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel
    let tools: ChromeTools

    /// `ToolSurfaceRegistry.live` is a plain computed property, so nothing
    /// observes it. The 1 Hz clock the lease countdowns already run on is a
    /// truthful cadence for a running indicator and costs no second timer.
    private var live: Set<ConsoleTool> {
        _ = model.clockTick
        return tools.registry.live
    }

    var body: some View {
        VStack(spacing: ConsoleToolMetrics.railSpacing) {
            ChromeRailButton(symbol: "house",
                             title: "Home",
                             shortcut: "⇧⌘H",
                             isOn: console.atHome && console.isLocalDeviceSelected,
                             isLive: false) {
                console.goHome()
            }

            Hairline()
                .padding(.horizontal, 2)

            let running = live
            ForEach(ConsoleTool.allCases) { tool in
                ChromeRailButton(symbol: tool.symbol,
                                 title: tool.title,
                                 shortcut: shortcutLabel(tool),
                                 isOn: tools.revealed == tool,
                                 isLive: running.contains(tool)) {
                    tools.toggle(tool, context: tools.context)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, ConsoleToolMetrics.railSpacing)
        .padding(.top, ConsoleToolMetrics.railSpacing)
        .frame(width: ChromeRailMetrics.railWidth)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ConsoleColor.hairline)
                .frame(width: 1)
        }
    }

    private func shortcutLabel(_ tool: ConsoleTool) -> String {
        "⇧⌘" + String(tool.shortcut.character).uppercased()
    }
}

/// One button, four call sites. Selection, hover, running indicator and help
/// text all live here, so no tool can grow its own affordance.
private struct ChromeRailButton: View {
    let symbol: String
    let title: String
    let shortcut: String
    let isOn: Bool
    let isLive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(ConsoleFont.subtitle)
                .symbolVariant(isOn ? .fill : .none)
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: ConsoleToolMetrics.toggleSize,
                       height: ConsoleToolMetrics.toggleSize)
                .background(
                    RoundedRectangle(cornerRadius: ConsoleMetrics.rowCorner, style: .continuous)
                        .fill(isOn ? ConsoleColor.selectionFill : .clear)
                )
                // The indicator sits *outside* the glyph's box so a live tool
                // and a revealed tool read as two different facts.
                .overlay(alignment: .bottomTrailing) {
                    if isLive {
                        StatusPip(tone: .good, size: 4, pulsing: true)
                            .offset(x: 3, y: 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: ConsoleMetrics.rowCorner)
        .help("\(title) (\(shortcut))")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - The panel

/// The embedded field the tools draw into. Owns its drag edge, its header, and
/// the one place a measured size becomes a proposed grid.
private struct ChromeToolPanel: View {
    let tool: ConsoleTool
    let tools: ChromeTools
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            dragHandle
            VStack(spacing: 0) {
                header
                Hairline()
                content
            }
        }
        .frame(width: width)
        .background(VisualEffectBackground(material: .sidebar, blendingMode: .withinWindow))
        // Nothing this panel contains may draw outside it. `frame(width:)`
        // proposes a width; it does not enforce one, so a subview that reports a
        // larger ideal size — a chip row, a terminal laid out to a stale grid —
        // simply overflows and paints across the rail and the titlebar strip.
        // The panel is a container with a hard edge, and this is that edge.
        .clipped()
    }

    /// The surface's measured character cell, read here so the panel *observes*
    /// it: `PTYSession` is `@Observable`, so a re-measure on a display change
    /// invalidates this body and the `onChange` below re-derives the grid.
    private var cellMetrics: TerminalCellMetrics? {
        (tools.registry.surface(for: tool) as? any PTYBackedSurface)?.cellMetrics
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: tool.symbol)
                .font(ConsoleFont.caption)
                .foregroundStyle(.secondary)
            Text(tool.title)
                .font(ConsoleFont.caption.weight(.semibold))
            Text(tools.context.subject)
                .font(ConsoleFont.caption)
                .foregroundStyle(SurfaceInk.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                // Yields before the tool's own name does when the panel is
                // narrow, rather than pushing it out of the header.
                .layoutPriority(-1)
            Spacer(minLength: 4)
            Button {
                tools.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(ConsoleFont.badge)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close \(tool.title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        Group {
            if tools.isTooNarrow {
                EmptyPanelView(
                    symbol: tool.symbol,
                    title: "Panel too narrow",
                    detail: "\(tool.title) needs at least \(TerminalGrid.minimum.columns) columns "
                        + "and \(TerminalGrid.minimum.rows) rows to draw honestly. "
                        + "Drag the panel's edge, or widen the window.")
            } else {
                tools.registry.surface(for: tool).makeView()
                    // Identity, because the two pty-backed surfaces are the same
                    // *type*. Terminal and Files both resolve to a
                    // `PTYTerminalView` at the same position in the tree, so
                    // switching between them looks to SwiftUI like the same view
                    // with new values: it calls `updateNSView`, which is
                    // deliberately empty, instead of `makeNSView`. The panel kept
                    // whichever host it was given first — open the shell, then
                    // Files, and the header said Files over the shell's prompt.
                    .id(tool)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // The measured size of the panel's content region — the only input
            // to the grid. `onChange` runs after layout, and the coalescer
            // holds the value until it stops moving, so no child process is
            // ever handed a size from inside a layout pass or an animation.
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        tools.propose(size: geometry.size)
                        tools.flushGeometry()
                    }
                    .onChange(of: geometry.size) { _, size in
                        tools.propose(size: size)
                    }
            }
        }
        // The other half of the grid's inputs. The panel has not moved, but the
        // cell it is drawing has, so the same pixels now mean a different number
        // of columns.
        .onChange(of: cellMetrics) { _, _ in tools.regrid() }
    }

    // MARK: Drag edge

    private var dragHandle: some View {
        // Drawn as a hairline, hit as a ten-point strip. The overhang is split
        // evenly either side and taken out of the layout with a negative inset,
        // so widening the target does not widen the seam you can see.
        Rectangle()
            .fill(ConsoleColor.hairline)
            .frame(width: ChromeRailMetrics.handleWidth)
            .padding(.horizontal, (ChromeRailMetrics.handleHitWidth
                                   - ChromeRailMetrics.handleWidth) / 2)
            .contentShape(Rectangle())
            .padding(.horizontal, -(ChromeRailMetrics.handleHitWidth
                                    - ChromeRailMetrics.handleWidth) / 2)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        // No animation while a pointer is driving the width:
                        // the panel should track the hand, and the coalescer is
                        // already suppressing the resizes this produces.
                        tools.requestedPanelWidth = (width - value.translation.width)
                            .clamped(ConsoleToolMetrics.panelMin, ConsoleToolMetrics.panelMax)
                    }
                    .onEnded { _ in tools.flushGeometry() }
            )
            .accessibilityHidden(true)
    }
}

private extension CGFloat {
    func clamped(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lower), upper)
    }
}
