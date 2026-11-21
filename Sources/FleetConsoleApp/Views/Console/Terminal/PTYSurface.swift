import AppKit
import SwiftTerm
import SwiftUI

@MainActor
protocol PTYBackedSurface: ToolSurface {
    var cellMetrics: TerminalCellMetrics { get }

    var reservedWidth: CGFloat { get }
    var chromeHeight: CGFloat { get }
}

extension PTYBackedSurface {
    var chromeHeight: CGFloat { 0 }
}

enum TerminalFont {
    private static let candidates = [
        "JetBrainsMonoNFM-Regular",
        "JetBrainsMonoNF-Regular",
        "IosevkaNF",
        "SymbolsNFM",
    ]

    static var panel: NSFont {
        let size = NSFont.preferredFont(forTextStyle: .callout).pointSize
        for name in candidates {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static var hasNerdGlyphs: Bool {
        candidates.contains { NSFont(name: $0, size: 12) != nil }
    }
}

extension TerminalCellMetrics {
    init(font: NSFont, scale: CGFloat) {
        let ctFont = font as CTFont
        let lineHeight = ceil(CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont))
        var characters: [UniChar] = [0x57]
        var glyphs: [CGGlyph] = [0]
        var advance = CGSize.zero
        if CTFontGetGlyphsForCharacters(ctFont, &characters, &glyphs, 1) {
            CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyphs, &advance, 1)
        } else {
            advance = ("W" as NSString).size(withAttributes: [.font: font])
        }
        self.init(width: max(1, (advance.width * scale).rounded() / scale),
                  height: max(1, ceil(lineHeight * scale) / scale))
    }
}

enum ToolBinary {
    static var loginShell: URL {
        if let pw = getpwuid(getuid()), let field = pw.pointee.pw_shell {
            let path = String(cString: field)
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/bin/zsh")
    }

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

    static func environment(withSearchPath: Bool) -> [String] {
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        if withSearchPath {
            env.append("PATH=" + searchPath.joined(separator: ":"))
        }
        return env
    }

    static func usableDirectory(_ url: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }
}

private final class ProcessReaper: @unchecked Sendable {
    var process: LocalProcess?
    private final class WeakReaper {
        weak var value: ProcessReaper?
        init(_ value: ProcessReaper) { self.value = value }
    }
    nonisolated(unsafe) private static var reapers: [WeakReaper] = []
    private static let cleanup = DispatchGroup()
    nonisolated(unsafe) private static let terminationObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { _ in
        for reaper in reapers.compactMap(\.value) { reaper.reapNow() }
        cleanup.wait()
    }

    init() {
        _ = Self.terminationObserver
        Self.reapers.removeAll { $0.value == nil }
        Self.reapers.append(WeakReaper(self))
    }

    deinit { reapNow() }

    func reapNow(waitForExit: Bool = false, completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard let process else {
            if waitForExit { Self.cleanup.wait() }
            if let completion { Task { @MainActor in completion() } }
            return
        }
        self.process = nil
        let pid = process.shellPid
        var child = siginfo_t()
        guard pid > 0, waitid(P_PID, id_t(pid), &child, WEXITED | WNOHANG | WNOWAIT) == 0 else {
            if waitForExit { Self.cleanup.wait() }
            if let completion { Task { @MainActor in completion() } }
            return
        }
        let group: pid_t? = getpgid(pid) == pid && pid != getpgrp() ? pid : nil
        if let group { kill(-group, SIGTERM) }
        process.terminate()
        let work = Self.cleanup
        work.enter()
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            var child = siginfo_t()
            let stillOwned = pid > 0 && waitid(P_PID, id_t(pid), &child, WEXITED | WNOHANG | WNOWAIT) == 0
            if stillOwned {
                if let group, getpgid(pid) == group { kill(-group, SIGKILL) }
                else { kill(pid, SIGKILL) }
            }
            var status: Int32 = 0
            if pid > 0 { _ = waitpid(pid, &status, 0) }
            work.leave()
            await completion?()
        }
        if waitForExit { work.wait() }
    }

    func childExited() { reapNow() }
}

@MainActor
final class PTYHostView: NSView {
    let terminal: LocalProcessTerminalView

    private(set) var cell: TerminalCellMetrics
    var onCellChange: ((TerminalCellMetrics) -> Void)?
    var onWindowClose: (() -> Void)?

    private weak var hostWindow: NSWindow?
    private nonisolated(unsafe) var closeObserver: NSObjectProtocol?

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
        terminal.autoresizingMask = []
        terminal.font = font
        addSubview(terminal)
        applyAppearance()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
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

    func apply(_ grid: TerminalGrid) {
        guard cell.isUsable else { return }
        terminal.setFrameSize(size(for: grid))

        let dimensions = terminal.terminalDimensions
        if dimensions.cols != grid.columns || dimensions.rows != grid.rows {
            terminal.setFrameSize(CGSize(
                width: terminal.frame.width + CGFloat(grid.columns - dimensions.cols) * cell.width,
                height: terminal.frame.height + CGFloat(grid.rows - dimensions.rows) * cell.height))
        }
        needsLayout = true
    }

    var reservedWidth: CGFloat {
        if terminal.scrollerStyle == .legacy {
            return NSScroller.scrollerWidth(for: .regular, scrollerStyle: terminal.scrollerStyle)
        }
        return 0
    }

    private func size(for grid: TerminalGrid) -> CGSize {
        CGSize(width: cell.width * CGFloat(grid.columns) + reservedWidth + Self.flooringGuard,
               height: cell.height * CGFloat(grid.rows) + Self.flooringGuard)
    }

    override func layout() {
        super.layout()
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

    private func remeasure() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let measured = TerminalCellMetrics(font: terminal.font, scale: scale)
        guard measured != cell else { return }
        cell = measured
        onCellChange?(measured)
    }

    private func applyAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            terminal.configureNativeColors()
            layer?.backgroundColor = terminal.nativeBackgroundColor.cgColor
        }
        terminal.needsDisplay = true
    }
}

@MainActor
@Observable
final class PTYSession {
    enum Phase: Equatable {
        case idle
        case running
        case stopping
        case exited(Int32?)
    }

    struct Launch: Equatable {
        var executable: URL
        var arguments: [String] = []
        var argv0: String?
        var workingDirectory: URL
        var environment: [String]
    }

    private(set) var phase: Phase = .idle
    private(set) var cell: TerminalCellMetrics
    private(set) var proposed: TerminalGrid?
    private(set) var forwarded: TerminalGrid?
    private(set) var launch: Launch?

    @ObservationIgnored let host: PTYHostView
    @ObservationIgnored private let bridge = Bridge()
    @ObservationIgnored private let reaper = ProcessReaper()
    @ObservationIgnored private var deferredLaunch: Launch?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var pendingInput: [String] = []

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

    var reservedWidth: CGFloat { host.reservedWidth }

    var isTooNarrow: Bool {
        guard refusesBelowMinimum, let proposed else { return false }
        return !proposed.fitsMinimum
    }

    func ensureRunning(_ launch: Launch) {
        guard phase != .running else { return }
        if phase == .stopping { deferredLaunch = launch; return }
        spawn(launch)
    }

    func restart(_ launch: Launch) {
        terminate()
        ensureRunning(launch)
    }

    func settle(_ grid: TerminalGrid) {
        proposed = grid
        guard !refusesBelowMinimum || grid.fitsMinimum else {
            return
        }
        if grid != forwarded {
            forwarded = grid
            host.apply(grid)
        }
        if phase != .stopping, let deferred = deferredLaunch {
            deferredLaunch = nil
            spawn(deferred)
        }
    }

    func send(_ text: String) {
        guard phase == .running else {
            pendingInput.append(text)
            return
        }
        host.terminal.send(txt: text)
    }

    func terminate(waitForExit: Bool = false) {
        deferredLaunch = nil
        pendingInput.removeAll()
        guard phase == .running else {
            if phase == .idle { phase = .exited(nil) }
            if waitForExit { reaper.reapNow(waitForExit: true) }
            return
        }
        phase = .stopping
        let outgoing = generation
        reaper.reapNow(waitForExit: waitForExit) { [weak self] in
            guard let self, self.generation == outgoing, self.phase == .stopping else { return }
            self.phase = .exited(nil)
            if let deferred = self.deferredLaunch {
                self.deferredLaunch = nil
                self.spawn(deferred)
            }
        }
    }

    private func spawn(_ launch: Launch) {
        guard let grid = forwarded else {
            deferredLaunch = launch
            return
        }
        let attempt = UUID()
        generation = attempt
        host.apply(grid)
        self.launch = launch
        attemptSpawn(launch, attempt: attempt)
    }

    private func attemptSpawn(_ launch: Launch, attempt: UUID) {
        let result = host.terminal.process.startProcessChecked(
            executable: launch.executable.path,
            args: launch.arguments,
            environment: launch.environment,
            execName: launch.argv0,
            currentDirectory: launch.workingDirectory.path)
        switch result {
        case .success:
            guard generation == attempt else { return }
            phase = host.terminal.process.running ? .running : .exited(nil)
            reaper.process = host.terminal.process
            if phase == .running, !pendingInput.isEmpty {
                let queued = pendingInput
                pendingInput = []
                queued.forEach { host.terminal.send(txt: $0) }
            }
        case .failure(.alreadyRunning):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, self.generation == attempt,
                      self.phase == .stopping || self.phase == .exited(nil) else { return }
                self.attemptSpawn(launch, attempt: attempt)
            }
        case .failure:
            guard generation == attempt else { return }
            phase = .exited(nil)
        }
    }

    func focusTerminal() {
        host.window?.makeFirstResponder(host.terminal)
    }

    fileprivate func childExited(status: Int32?) {
        guard phase == .running || phase == .stopping else { return }
        reaper.childExited()
        phase = .exited(status)
        host.terminal.feed(text: "\r\n" + PTYSession.notice(for: status) + "\r\n")
        if let deferred = deferredLaunch {
            deferredLaunch = nil
            spawn(deferred)
        }
    }

    private static func notice(for status: Int32?) -> String {
        guard let status else { return "[process ended]" }
        return status == 0 ? "[process exited]" : "[process exited — status \(status)]"
    }

    private final class Bridge: LocalProcessTerminalViewDelegate, @unchecked Sendable {
        nonisolated(unsafe) weak var session: PTYSession?

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            MainActor.assumeIsolated { session?.childExited(status: exitCode) }
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}

struct PTYTerminalView: NSViewRepresentable {
    let host: PTYHostView

    func makeNSView(context: Context) -> PTYHostView { host }

    func updateNSView(_ nsView: PTYHostView, context: Context) {}
}

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
