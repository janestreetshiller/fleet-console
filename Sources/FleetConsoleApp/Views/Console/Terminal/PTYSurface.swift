import AppKit
import SwiftTerm
import SwiftUI

// Shared pseudo-terminal plumbing for the two PTY-backed chrome panels.
//
// The terminal and the file surface differ only in what they exec, so everything
// else lives here: measure the character cell, spawn a child in a pty, hand it a
// settled grid exactly once, and keep it warm across toggles.
//
// One structural decision drives the rest. `SwiftTerm.TerminalView` re-derives
// its own column count from its frame inside `setFrameSize`, which is precisely
// the per-frame `TIOCSWINSZ` + `SIGWINCH` that `ToolResizeCoalescer` exists to
// prevent. So the terminal is never the view SwiftUI resizes: it sits inside
// `PTYHostView`, whose bounds follow the sidebar spring freely while the
// terminal's own frame changes only when a settled `TerminalGrid` arrives. That
// makes "forward the settled grid straight to the pty" a single frame
// assignment, with no debounce of our own stacked on the host's.

// MARK: - Published cell metrics

/// Additive to `ToolSurface` rather than folded into it: the seam file is shared
/// with the rail and the interpreter, and only the two pty-backed panels have a
/// cell to publish. The host reaches for this with `as?` when it needs to turn a
/// panel's pixel size into a grid.
@MainActor
protocol PTYBackedSurface: ToolSurface {
    var cellMetrics: TerminalCellMetrics { get }

    /// Panel width that is spent before the first column can be drawn. See
    /// `TerminalGrid.fitting(_:cell:reservedWidth:)` — the host must measure the
    /// columns against what is actually left, or it hands back a grid that does
    /// not fit the panel it measured.
    var reservedWidth: CGFloat { get }
}

// MARK: - Font and cell

enum TerminalFont {
    /// A Nerd Font when one is installed, SF Mono when none is.
    ///
    /// SF Mono was the original choice — the same family `ConsoleFont.mono()`
    /// uses for ports, PIDs and paths — and it is a fine face for a shell. It
    /// carries no Private Use Area glyphs, though, and Yazi draws its entire
    /// file-type column out of that range. Every icon in the Files panel was
    /// rendering as tofu, which reads as a broken panel rather than as a missing
    /// font.
    ///
    /// The list is ordered most- to least-specific: a patched mono face first,
    /// then the symbols-only face, which CoreText will fall back into for the
    /// PUA range while keeping SF Mono for text. Nothing here is bundled — the
    /// app cannot ship JetBrains Mono — so the final fallback stays SF Mono and
    /// the panel keeps working with no Nerd Font at all, just without icons.
    /// PostScript names, not family names — `NSFont(name:)` takes the former and
    /// silently returns nil for the latter, which is how a plausible-looking
    /// "SymbolsNerdFontMono-Regular" sat in this list resolving to nothing. Each
    /// one below was verified against `NSFontManager.availableMembers`.
    private static let candidates = [
        "JetBrainsMonoNFM-Regular",   // JetBrainsMono NFM
        "JetBrainsMonoNF-Regular",    // JetBrainsMono NF
        "IosevkaNF",                  // Iosevka Nerd Font
        "SymbolsNFM",                 // Symbols Nerd Font Mono
    ]

    static var panel: NSFont {
        let size = NSFont.preferredFont(forTextStyle: .callout).pointSize
        for name in candidates {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Whether `panel` resolved to a face that can draw Yazi's icons. The Files
    /// panel says so rather than leaving the user to wonder why the column is
    /// blank.
    static var hasNerdGlyphs: Bool {
        candidates.contains { NSFont(name: $0, size: 12) != nil }
    }
}

extension TerminalCellMetrics {
    /// Measures the cell the way SwiftTerm does: ascent + descent + leading for
    /// the height, the advance of `W` for the width, both snapped to the backing
    /// store so adjacent cells cannot land on a half pixel.
    ///
    /// Re-derived rather than read back, because SwiftTerm keeps its own
    /// `cellDimension` internal and the host needs a cell *before* the first
    /// frame is handed out. Matching the formula is what lets
    /// `PTYHostView.apply(_:)` land on the grid it asked for in one step instead
    /// of converging on it over several `SIGWINCH`es.
    init(font: NSFont, scale: CGFloat) {
        let ctFont = font as CTFont
        let lineHeight = ceil(CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont))
        var glyph = CTFontGetGlyphWithName(ctFont, "W" as CFString)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &advance, 1)
        self.init(width: max(1, ceil(advance.width * scale) / scale),
                  height: max(1, ceil(lineHeight * scale) / scale))
    }
}

// MARK: - Child processes

enum ToolBinary {
    /// The user's login shell, from the password database rather than `$SHELL`.
    /// A GUI process does not inherit the user's interactive environment, so
    /// `$SHELL` is whatever launchd had; `getpwuid` is the same source
    /// Terminal.app reads.
    static var loginShell: URL {
        if let pw = getpwuid(getuid()), let field = pw.pointee.pw_shell {
            let path = String(cString: field)
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/bin/zsh")
    }

    /// Finds `name` the way a login shell would, without running one. The
    /// inherited `PATH` comes first, then the prefixes package managers actually
    /// install into — a Finder-launched app inherits a four-entry `PATH`, so
    /// refusing to look past it would report a tool missing on a machine that
    /// has it.
    static func resolve(_ name: String) -> URL? {
        searchPath
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var searchPath: [String] {
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let prefixes = ["/opt/homebrew/bin",
                        "/usr/local/bin",
                        NSHomeDirectory() + "/.cargo/bin",
                        NSHomeDirectory() + "/.local/bin",
                        "/usr/bin",
                        "/bin"]
        var seen = Set<String>()
        return (inherited + prefixes).filter { seen.insert($0).inserted }
    }

    /// SwiftTerm's defaults carry `TERM`, `COLORTERM` and a UTF-8 locale, and
    /// deliberately omit `PATH` — a login shell rebuilds its own from the
    /// profile. A tool exec'd directly has no such chance, so it gets the same
    /// search path we resolved it with, otherwise its previewers and helpers
    /// (`file`, `unar`, `$EDITOR`) are simply absent.
    static func environment(withSearchPath: Bool) -> [String] {
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        if withSearchPath {
            env.append("PATH=" + searchPath.joined(separator: ":"))
        }
        return env
    }

    /// A directory the child can actually start in. `forkpty`'s `chdir` failure
    /// is silent, which would drop the child in the app bundle's cwd and quietly
    /// contradict the panel header.
    static func usableDirectory(_ url: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }
}

/// Sends the child its `SIGTERM` and waits for it, from an object that is *not*
/// main-actor bound. `LocalProcess.deinit` deliberately never signals the child,
/// and `LocalProcess.terminate()` cancels the very dispatch source that would
/// have `waitpid`ed — so without this a closed window leaves a live shell, and a
/// restart leaves a zombie for the life of the app.
///
/// Only ever touched on the main queue; the `@unchecked Sendable` is for the
/// notification closure.
private final class ProcessReaper: @unchecked Sendable {
    var process: LocalProcess?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reapNow()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        reapNow()
    }

    func reapNow() {
        guard let process, process.running else { return }
        let pid = process.shellPid
        process.terminate()
        ProcessReaper.wait(for: pid)
    }

    /// `SIGTERM` is asynchronous, so the wait cannot happen inline. Escalates
    /// rather than parking a thread forever on a child that ignores it.
    static func wait(for pid: pid_t) {
        guard pid != 0 else { return }
        Task.detached(priority: .utility) {
            var status: Int32 = 0
            for _ in 0..<20 {
                if waitpid(pid, &status, WNOHANG) != 0 { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
            kill(pid, SIGKILL)
            _ = waitpid(pid, &status, 0)
        }
    }
}

// MARK: - The AppKit host

/// Container for the terminal view. Exists so that SwiftUI can resize *this*
/// view as often as it likes without any of those sizes reaching the child
/// process: the terminal keeps whatever frame the last settled grid gave it, and
/// the slack shows as terminal background at the trailing and bottom edges.
@MainActor
final class PTYHostView: NSView {
    let terminal: LocalProcessTerminalView

    private(set) var cell: TerminalCellMetrics
    /// Called when a display change makes the measured cell stale, so the host
    /// can recompute its grid against the new one.
    var onCellChange: ((TerminalCellMetrics) -> Void)?
    var onWindowClose: (() -> Void)?

    private weak var hostWindow: NSWindow?
    /// The observer token, written once in `init` and read once in `deinit`.
    /// `deinit` is nonisolated in Swift 6 and the token's existential type is not
    /// Sendable, so the access has to be spelled out as unchecked — which is
    /// accurate here: both ends of its life are on the main thread, and nothing
    /// else ever touches it.
    private nonisolated(unsafe) var closeObserver: NSObjectProtocol?

    /// Absorbs float error in `width / cellWidth`, which floors: a settled 80
    /// columns must not become 79 because the last cell was a millionth of a
    /// point short. Cannot overshoot while a cell is wider than half a point.
    private static let flooringGuard: CGFloat = 0.5

    init(font: NSFont) {
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        cell = TerminalCellMetrics(font: font, scale: scale)
        let initial = CGRect(origin: .zero,
                             size: CGSize(width: cell.width * CGFloat(TerminalGrid.minimum.columns),
                                          height: cell.height * CGFloat(TerminalGrid.minimum.rows)))
        terminal = LocalProcessTerminalView(frame: initial)
        super.init(frame: initial)

        clipsToBounds = true
        wantsLayer = true
        // Frame-driven on purpose: the whole point is that the superview's
        // layout does not propagate a size onto the terminal.
        terminal.autoresizingMask = []
        terminal.font = font
        addSubview(terminal)
        applyAppearance()

        // A window can be closed while this panel is toggled off and detached,
        // so the notification is matched against the window we last belonged to
        // rather than the one we are in now.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            // `queue: .main` already puts this block on the main thread, so the
            // isolation below is asserted rather than hopped. What crosses into it
            // is the window's `ObjectIdentifier`, not the window: `NSWindow` is not
            // Sendable, and identity is the only question being asked of it.
            let closing = (note.object as? NSWindow).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let closing,
                      closing == self.hostWindow.map(ObjectIdentifier.init) else { return }
                self.onWindowClose?()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not loaded from a nib") }

    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }

    /// Hands a settled grid to the pty. One frame assignment, one `TIOCSWINSZ`,
    /// one `SIGWINCH`, one TUI repaint.
    ///
    /// Deliberately does *not* use `TerminalView.resize(cols:rows:)`, which
    /// appends a DECSTR soft reset — that clears application-cursor mode and
    /// unhides the cursor, so a running full-screen TUI would lose its arrow
    /// keys and grow a stray caret on every resize.
    func apply(_ grid: TerminalGrid) {
        guard cell.isUsable else { return }
        terminal.setFrameSize(size(for: grid))

        // Self-correcting second pass: if SwiftTerm's width→columns arithmetic
        // ever disagrees with our re-derived cell, one extra signal is cheaper
        // than a permanently wrong grid.
        let emulator = terminal.getTerminal()
        if emulator.cols != grid.columns || emulator.rows != grid.rows {
            terminal.setFrameSize(CGSize(
                width: terminal.frame.width + CGFloat(grid.columns - emulator.cols) * cell.width,
                height: terminal.frame.height + CGFloat(grid.rows - emulator.rows) * cell.height))
        }
        needsLayout = true
    }

    /// SwiftTerm reserves the scroller's width out of the drawable area whatever
    /// the scroller's visibility, so the columns have to be measured against what
    /// is left. Published so the host that computes the grid measures against the
    /// same number this view lays out against.
    var reservedWidth: CGFloat {
        NSScroller.scrollerWidth(for: .regular, scrollerStyle: terminal.scrollerStyle)
    }

    private func size(for grid: TerminalGrid) -> CGSize {
        CGSize(width: cell.width * CGFloat(grid.columns) + reservedWidth + Self.flooringGuard,
               height: cell.height * CGFloat(grid.rows) + Self.flooringGuard)
    }

    override func layout() {
        super.layout()
        // Pinned top-left: the prompt stays where the eye left it, and the slack
        // between the settled grid and the panel's bounds sits at the far edge.
        //
        // Not clamped to zero. A grid that overshoots its panel — which is a bug
        // upstream, but one this view should degrade honestly under — used to be
        // pushed *down* until its first rows sat above the top edge and were
        // clipped away, so a freshly spawned shell showed a panel with no prompt
        // in it. Letting the origin go negative keeps the top-left corner where
        // the name says it is and loses the overshoot off the bottom instead.
        terminal.setFrameOrigin(CGPoint(x: 0, y: bounds.height - terminal.frame.height))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { hostWindow = window }
        remeasure()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        remeasure()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    /// The cell is a function of the font *and* the display, so moving the window
    /// between a Retina and a non-Retina screen changes it.
    private func remeasure() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let measured = TerminalCellMetrics(font: terminal.font, scale: scale)
        guard measured != cell else { return }
        cell = measured
        onCellChange?(measured)
    }

    /// Text and background come from the system's semantic colours so the panel
    /// follows the window's appearance. Resolved inside the current drawing
    /// appearance because SwiftTerm snapshots the background into an RGB triple
    /// for its own fills.
    private func applyAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            terminal.configureNativeColors()
            layer?.backgroundColor = terminal.nativeBackgroundColor.cgColor
        }
        terminal.needsDisplay = true
    }
}

// MARK: - Session

/// Owns one child process and the view it draws into. The panels above are thin:
/// they choose what to exec and answer the `ToolSurface` questions from here.
@MainActor
@Observable
final class PTYSession {
    enum Phase: Equatable {
        case idle
        case running
        /// Raw `wait` status, as SwiftTerm hands it over.
        case exited(Int32?)
    }

    struct Launch: Equatable {
        var executable: URL
        var arguments: [String] = []
        /// Unix `argv[0]`. A leading dash is how a shell is asked to behave as a
        /// login shell.
        var argv0: String?
        var workingDirectory: URL
        var environment: [String]
    }

    private(set) var phase: Phase = .idle
    private(set) var cell: TerminalCellMetrics
    /// Last grid the host settled on, forwarded or not.
    private(set) var proposed: TerminalGrid?
    /// Last grid the child was actually told about.
    private(set) var forwarded: TerminalGrid?
    private(set) var launch: Launch?

    @ObservationIgnored let host: PTYHostView
    @ObservationIgnored private let bridge = Bridge()
    @ObservationIgnored private let reaper = ProcessReaper()
    /// A launch that is waiting for its first settled grid.
    @ObservationIgnored private var deferredLaunch: Launch?

    /// Whether a grid below `TerminalGrid.minimum` may reach the child at all.
    /// Yazi's three panes collapse under it, so the file surface refuses and
    /// shows a too-narrow state; a shell reflows honestly at any width, so the
    /// terminal panel does not.
    @ObservationIgnored let refusesBelowMinimum: Bool

    init(font: NSFont = TerminalFont.panel, refusesBelowMinimum: Bool) {
        self.refusesBelowMinimum = refusesBelowMinimum
        host = PTYHostView(font: font)
        cell = host.cell
        host.terminal.processDelegate = bridge
        bridge.session = self
        host.onCellChange = { [weak self] measured in self?.cell = measured }
        host.onWindowClose = { [weak self] in self?.terminate() }
    }

    /// See `PTYHostView.reservedWidth`. Forwarded so a panel can answer
    /// `PTYBackedSurface` without reaching through to the view.
    var reservedWidth: CGFloat { host.reservedWidth }

    var isTooNarrow: Bool {
        guard refusesBelowMinimum, let proposed else { return false }
        return !proposed.fitsMinimum
    }

    /// Start the child if it is not already running. Never disturbs a live one —
    /// the whole point of keeping it warm.
    func ensureRunning(_ launch: Launch) {
        guard phase != .running else { return }
        spawn(launch)
    }

    /// Replace a live child with one launched somewhere else. Safe to do
    /// synchronously: `terminate()` cancels SwiftTerm's exit dispatch source, so
    /// the outgoing child cannot report back over the top of the new one.
    func restart(_ launch: Launch) {
        terminate()
        spawn(launch)
    }

    /// A settled, cell-aligned grid from the host. Forwarded as-is; the host has
    /// already waited for the animation to stop.
    func settle(_ grid: TerminalGrid) {
        proposed = grid
        guard !refusesBelowMinimum || grid.fitsMinimum else {
            // Leave the child at its last honest size. It keeps painting that
            // grid behind the too-narrow state, and reappears without a reflow.
            return
        }
        if grid != forwarded {
            forwarded = grid
            host.apply(grid)
        }
        if let deferred = deferredLaunch {
            deferredLaunch = nil
            spawn(deferred)
        }
    }

    func terminate() {
        guard phase == .running else { return }
        reaper.reapNow()
        phase = .exited(nil)
    }

    private func spawn(_ launch: Launch) {
        // The child inherits its window size at `forkpty`, so there is no point
        // starting one before the host has settled a grid — it would open at
        // SwiftTerm's default 80x25 and be resized a frame later.
        guard let grid = forwarded else {
            deferredLaunch = launch
            return
        }
        host.apply(grid)
        self.launch = launch
        host.terminal.startProcess(executable: launch.executable.path,
                                   args: launch.arguments,
                                   environment: launch.environment,
                                   execName: launch.argv0,
                                   currentDirectory: launch.workingDirectory.path)
        let process = host.terminal.process
        reaper.process = process
        // `startProcess` reports failure by simply not running: `forkpty` failed,
        // or `execve` did and the child already `_exit(127)`ed.
        phase = process?.running == true ? .running : .exited(nil)
    }

    /// Focus for the panel that has just been opened. Called on first spawn only:
    /// a selection change while the panel is open must not steal the caret from
    /// the sidebar or the search field.
    func focusTerminal() {
        host.window?.makeFirstResponder(host.terminal)
    }

    fileprivate func childExited(status: Int32?) {
        // An exit we did not ask for. Ignore the late report of a child we
        // replaced ourselves — that one is already accounted for.
        guard host.terminal.process?.running != true else { return }
        phase = .exited(status)
        // The scrollback is the evidence for *why* it exited, so the view keeps
        // showing it and the chrome's running indicator carries the fact. The
        // notice goes into that scrollback rather than over it.
        host.terminal.feed(text: "\r\n" + PTYSession.notice(for: status) + "\r\n")
        if let pid = host.terminal.process?.shellPid { ProcessReaper.wait(for: pid) }
    }

    /// SwiftTerm passes the raw `wait` status through as an "exit code", so it is
    /// decoded here rather than printed as-is.
    private static func notice(for status: Int32?) -> String {
        guard let status else { return "[process ended]" }
        let signal = status & 0x7f
        if signal != 0 { return "[process killed — signal \(signal)]" }
        let code = (status >> 8) & 0xff
        return code == 0 ? "[process exited]" : "[process exited — status \(code)]"
    }

    /// SwiftTerm's process delegate is not main-actor bound, but every callback
    /// is delivered on the main queue (`LocalProcess` defaults its dispatch queue
    /// to `.main`), so the isolation is asserted rather than hopped — a hop would
    /// let a resize land between the exit and our record of it.
    private final class Bridge: LocalProcessTerminalViewDelegate, @unchecked Sendable {
        /// The delegate protocol's methods are nonisolated, so the bridge itself has
        /// to be sendable to be handed to SwiftTerm at all. The unchecked part is
        /// this one reference, and it is safe for the reason in the comment above:
        /// every callback arrives on the main queue, so this is only ever read
        /// there — the same thread that set it.
        nonisolated(unsafe) weak var session: PTYSession?

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            MainActor.assumeIsolated { session?.childExited(status: exitCode) }
        }

        // The pty is the authority on its own size, and the child owns its title
        // and its cwd. Nothing in the chrome reads them back.
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}

// MARK: - SwiftUI surface

/// The terminal itself. `makeNSView` returns a view the session already owns,
/// which is what keeps the process and its scrollback alive across panel
/// toggles and SwiftUI rebuilds.
struct PTYTerminalView: NSViewRepresentable {
    let host: PTYHostView

    func makeNSView(context: Context) -> PTYHostView { host }

    // Geometry arrives through `ToolSurface.resize(to:)` after the host has
    // coalesced it. Reacting here as well would put a second, un-coalesced path
    // to the pty back in.
    func updateNSView(_ nsView: PTYHostView, context: Context) {}
}

/// A pty panel's content: the terminal, or an honest reason it is not showing.
/// No padding of its own — the host measures this area to compute the grid, and
/// an inset here would be an inset the grid does not know about.
struct PTYPanelView: View {
    let session: PTYSession
    let tooNarrowDetail: String

    var body: some View {
        Group {
            if session.isTooNarrow {
                EmptyPanelView(symbol: "arrow.left.and.right",
                                    title: "Too narrow",
                                    detail: tooNarrowDetail)
            } else {
                PTYTerminalView(host: session.host)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ConsoleMetrics.rowCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConsoleMetrics.rowCorner, style: .continuous)
                .strokeBorder(ConsoleColor.hairline)
        }
    }
}
