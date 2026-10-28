import SwiftUI

// The chrome tool rail — the seam shared by the panels that hang off the
// console window's chrome: a terminal and a Yazi file surface.
//
// This file exists for one reason. The panels live in a spring-loaded sidebar
// field, and both are backed by a PTY running a full-screen TUI. A
// panel whose width animates would hand that TUI a new column count on every
// frame of the spring, and Yazi would redraw through the whole animation — the
// tearing this design is explicitly meant to avoid. So geometry is never
// forwarded to a child process while it is still in motion: the panel proposes
// sizes, `ToolResizeCoalescer` waits for them to stop changing, and only a
// settled, cell-aligned `TerminalGrid` ever reaches a surface.

// MARK: - Identity

/// The chrome tools. One case per toggle in the window chrome; the rail
/// draws itself from `allCases`, so adding a tool here is the only edit needed
/// to give it a toggle.
enum ConsoleTool: String, CaseIterable, Identifiable, Sendable {
    case terminal
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .files: return "Files"
        }
    }

    /// Chrome toggle glyph. Deliberately plain SF Symbols.
    var symbol: String {
        switch self {
        case .terminal: return "terminal"
        case .files: return "folder"
        }
    }

    /// Intended chrome shortcut. ⌘0 and ⌘1…⌘n are already spoken for by the
    /// dashboard and the modules — `n` is `ConsoleModule.allCases.count`, not a
    /// number written down here — ⇧⌘H by Home and ⌘K/⌘R by search and refresh,
    /// so the tools take the rest of the shifted range.
    var shortcut: KeyEquivalent {
        switch self {
        case .terminal: return "t"
        case .files: return "f"
        }
    }

    /// Whether this tool drives a pseudo-terminal.
    var isPTYBacked: Bool {
        switch self {
        case .terminal, .files: return true
        }
    }
}

// MARK: - Geometry

/// Character-cell size for the panel's monospaced font, measured once by the
/// surface that owns the font and handed back here so the math is shared.
struct TerminalCellMetrics: Equatable, Sendable {
    var width: CGFloat
    var height: CGFloat

    /// A sane non-zero default so a grid computed before the first text
    /// measurement is merely wrong rather than a divide-by-zero.
    static let placeholder = TerminalCellMetrics(width: 7, height: 15)

    var isUsable: Bool { width > 0.5 && height > 0.5 }
}

/// A whole-cell terminal size. Never fractional: a PTY has no concept of half a
/// column, and rounding at the last moment is what produces a torn frame.
struct TerminalGrid: Equatable, Sendable {
    var columns: Int
    var rows: Int

    /// The floor below which a full-screen TUI cannot be honestly drawn. Yazi's
    /// three-pane layout collapses under roughly 40 columns, and anything under
    /// 10 rows loses its status line. A panel narrower than this shows a
    /// "too narrow" state instead of a mangled one — the same principle the rest
    /// of the app follows by refusing to display a number it cannot stand behind.
    static let minimum = TerminalGrid(columns: 40, rows: 10)

    var fitsMinimum: Bool {
        columns >= Self.minimum.columns && rows >= Self.minimum.rows
    }

    /// Quantize an available pixel size down to whole cells. Floors rather than
    /// rounds, so the grid always fits inside the panel and the last column is
    /// never clipped mid-glyph.
    ///
    /// `reservedWidth` is the part of the panel a surface spends before it can
    /// draw a single column — for a SwiftTerm view, the scroller's width, which
    /// it subtracts whatever the scroller's visibility
    /// (`TerminalView.getEffectiveWidth`). Measuring the columns against the
    /// whole panel instead is how a grid ends up wider than the panel that asked
    /// for it, and `PTYHostView` clips the difference off the trailing edge.
    static func fitting(_ size: CGSize,
                        cell: TerminalCellMetrics,
                        reservedWidth: CGFloat = 0) -> TerminalGrid {
        guard cell.isUsable, size.width > 0, size.height > 0 else { return minimum }
        let drawable = max(0, size.width - reservedWidth)
        return TerminalGrid(columns: max(1, Int((drawable / cell.width).rounded(.down))),
                            rows: max(1, Int((size.height / cell.height).rounded(.down))))
    }
}

// MARK: - Resize discipline

/// Holds a proposed grid until it stops changing, then emits it once.
///
/// SwiftUI hands us a new size on every frame of the sidebar spring. Forwarding
/// each one costs a `TIOCSWINSZ` plus a `SIGWINCH` and a full TUI repaint, which
/// is both the visible tearing and a real cost — Yazi redraws its whole tree per
/// signal. Waiting for quiescence turns an entire animation into one resize.
@MainActor
final class ToolResizeCoalescer {
    /// Long enough to outlast `ConsoleAnimation`-class springs, short enough that
    /// a deliberate drag still feels like it lands immediately.
    private let quietPeriod: Duration
    private var pending: TerminalGrid?
    private var settled: TerminalGrid?
    private var task: Task<Void, Never>?
    private let onSettle: (TerminalGrid) -> Void

    init(quietPeriod: Duration = .milliseconds(120),
         onSettle: @escaping (TerminalGrid) -> Void) {
        self.quietPeriod = quietPeriod
        self.onSettle = onSettle
    }

    /// Called as often as the layout system likes. Cheap when the grid has not
    /// actually changed cells, which is the common case mid-spring: a few pixels
    /// of width usually map to the same column count.
    func propose(_ grid: TerminalGrid) {
        guard grid != pending else { return }
        pending = grid
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.quietPeriod)
            guard !Task.isCancelled else { return }
            self.flush()
        }
    }

    /// Emit immediately — for the end of an explicit drag, or a panel that has
    /// just been revealed and should not wait out the quiet period before its
    /// first paint.
    func flush() {
        task?.cancel()
        task = nil
        guard let grid = pending, grid != settled else { return }
        settled = grid
        onSettle(grid)
    }

    /// Forget the settled value so the next proposal is treated as fresh. Used
    /// when a surface is torn down and rebuilt against a new process.
    func reset() {
        task?.cancel()
        task = nil
        pending = nil
        settled = nil
    }

    deinit { task?.cancel() }
}

// MARK: - Context

/// What a tool should open against. Assembled by the chrome from the console's
/// current selection so that opening the file surface on a selected service
/// lands in that service's working directory rather than `$HOME`.
struct ToolContext: Equatable, Sendable {
    /// Working directory for a PTY-backed tool.
    var workingDirectory: URL
    /// Human-readable description of the current selection, for the panel's
    /// header.
    var subject: String
    /// The selected service's id, when a service is selected.
    var serviceID: String?

    init(workingDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
         subject: String = "This Mac",
         serviceID: String? = nil) {
        self.workingDirectory = workingDirectory
        self.subject = subject
        self.serviceID = serviceID
    }
}

// MARK: - Surface contract

/// Implemented by each tool panel. The host owns visibility and geometry; the
/// surface owns its child process and its rendering.
///
/// Deliberately class-bound and main-actor: every implementation wraps either an
/// `NSView` or an `@Observable` model, and none of them is a value type.
@MainActor
protocol ToolSurface: AnyObject {
    var tool: ConsoleTool { get }

    /// Whether the surface currently holds a live child process. The chrome uses
    /// this to draw the toggle's running indicator, and to decide whether
    /// revealing the panel needs to start something.
    var isLive: Bool { get }

    /// Reveal or first-open against a context. Called on toggle-on, and again
    /// when the selection changes while the panel is open.
    func activate(context: ToolContext)

    /// A settled, cell-aligned size. Only ever called by the host through a
    /// `ToolResizeCoalescer`, never directly from a layout pass.
    func resize(to grid: TerminalGrid)

    /// Toggle-off. Whether this tears down the child process or leaves it warm
    /// is the surface's decision — a shell with scrollback is worth keeping.
    func deactivate()

    /// The panel's content. Type-erased on purpose: the host embeds the
    /// `NSViewRepresentable` PTY wrappers behind one rail, and the rail should
    /// not be generic over which one is showing.
    func makeView() -> AnyView
}

/// Resolves a tool to its surface, one instance per tool for the window's
/// lifetime. The host holds this; the surfaces hold the child processes.
@MainActor
final class ToolSurfaceRegistry {
    private var surfaces: [ConsoleTool: any ToolSurface] = [:]

    func surface(for tool: ConsoleTool) -> any ToolSurface {
        if let existing = surfaces[tool] { return existing }
        let made: any ToolSurface
        switch tool {
        case .terminal: made = TerminalPanel()
        case .files: made = FilesPanel()
        }
        surfaces[tool] = made
        return made
    }

    /// Live tools, for the chrome's running indicators.
    var live: Set<ConsoleTool> {
        Set(surfaces.filter { $0.value.isLive }.keys)
    }

    func deactivateAll() {
        for surface in surfaces.values { surface.deactivate() }
    }

    func closeTerminalSessions() {
        (surfaces[.terminal] as? TerminalPanel)?.windowClosed()
    }

    func resumeTerminal() {
        (surfaces[.terminal] as? TerminalPanel)?.windowReopened()
    }
}

/// Shared "this panel cannot draw itself yet" state. Used by a surface whose
/// backing tool is missing or whose panel is too narrow to render honestly —
/// the same instinct as the rest of the app, which would rather say it does not
/// know than show something it cannot stand behind.
struct EmptyPanelView: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(ConsoleFont.emptyGlyph)
                .foregroundStyle(SurfaceInk.secondary)
            Text(title)
                .font(ConsoleFont.subtitle.weight(.medium))
                .foregroundStyle(.secondary)
            Text(detail)
                .font(ConsoleFont.caption)
                .foregroundStyle(SurfaceInk.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ConsoleMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Panel tokens

/// Chrome-panel metrics. Kept in its own namespace rather than appended to
/// `ConsoleMetrics` so the tool rail can land without touching the token file;
/// fold it in once the chrome work settles.
enum ConsoleToolMetrics {
    /// A representative character cell for the panel font at the default text
    /// size — JetBrains Mono NFM and SF Mono both measure 8×16 at 12pt. Used
    /// only to size the *panel*; the grid handed to a child process is always
    /// computed from the cell the surface actually measured.
    static let referenceCell = TerminalCellMetrics(width: 8, height: 16)

    /// What SwiftTerm takes off the drawable width for its scroller, whatever
    /// the scroller's visibility (`TerminalView.getEffectiveWidth`). 17pt at
    /// macOS's overlay scroller style.
    static let scrollerReserve: CGFloat = 17

    /// Panel bounds inside the sidebar field.
    ///
    /// The minimum is what `TerminalGrid.minimum` actually costs — its columns
    /// at the reference cell, *plus* the scroller reserve and the drag edge,
    /// neither of which can draw a column. This said it was "derived from
    /// `TerminalGrid.minimum`" while being 40 × 8 exactly, which left the two
    /// non-drawing strips out and made 320pt a width at which the file surface
    /// could only ever report itself too narrow to draw.
    ///
    /// The claim that used to sit here — "the window's 1060pt minimum leaves the
    /// panel 346pt" — was false twice over: the minimum was 780, not 1060, and
    /// at 780 the column reserve alone was 786, so the panel's floor did not fit
    /// at the narrowest window by a margin of −440pt. The window's minimum is now
    /// *derived from* this floor (`ConsoleLayout.minimumContentWidth`) rather
    /// than asserted to accommodate it, and `ConsoleLayoutTests` proves the
    /// arrangement balances there exactly.
    static let panelMin: CGFloat = referenceCell.width * CGFloat(TerminalGrid.minimum.columns)
        + scrollerReserve
        + ChromeRailMetrics.handleWidth
    /// The resting width: the minor section of the composed window, snapped to
    /// the ladder. 377 rather than the previous 420 — a panel is a guest of the
    /// three columns, and taking the golden minor rather than an arbitrary 420
    /// is what lets the inspector stay up beside it at the composed size.
    static let panelIdeal: CGFloat = 377
    static let panelMax: CGFloat = 610

    /// Toggle button in the chrome rail.
    static let toggleSize: CGFloat = 22
    static let railSpacing: CGFloat = 6

    /// The spring the panel opens with. Slower than `ConsoleAnimation.selection`
    /// because it moves a whole column, and the coalescer above absorbs the cost.
    static let reveal = Animation.spring(response: 0.34, dampingFraction: 0.86)
}
