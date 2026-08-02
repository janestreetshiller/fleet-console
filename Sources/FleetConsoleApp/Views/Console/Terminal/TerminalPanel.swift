import SwiftUI

// The shell surface — backed by a real PTY running the user's login shell.
//
// Design decisions:
//   - The shell is kept warm across deactivate/activate cycles. A shell with
//     scrollback and a running process is more valuable than a clean slate, and
//     re-spawning on every toggle is jarring. `terminate()` is only called when
//     the working directory changes — a new context is a genuine reason to
//     land in the right place.
//   - `isLive` mirrors the session's `.running` phase so the chrome rail's
//     pip animates only while a child is actually alive.
//   - First activate defers the spawn until the first settled grid arrives
//     (handled inside PTYSession itself). The panel never hands a 0×0 grid to
//     a child.
//   - `PTYBackedSurface` is adopted so the host can read `cellMetrics` back
//     when computing the grid; the layout of the panel's content region is the
//     only input to `TerminalGrid.fitting`.

@MainActor
final class TerminalPanel: PTYBackedSurface {
    let tool: ConsoleTool = .terminal

    private let session = PTYSession(refusesBelowMinimum: false)
    private var currentContext = ToolContext()
    private var activated = false

    // MARK: PTYBackedSurface

    var cellMetrics: TerminalCellMetrics { session.cell }

    var reservedWidth: CGFloat { session.reservedWidth }

    var isLive: Bool { session.phase == .running }

    // MARK: ToolSurface

    func activate(context: ToolContext) {
        let dir = ToolBinary.usableDirectory(context.workingDirectory)

        if !activated {
            // First open: build the launch spec and let the session defer until
            // the first settled grid arrives.
            currentContext = context
            activated = true
            session.ensureRunning(makeLaunch(dir: dir))
            session.focusTerminal()
            return
        }

        // Already activated. If the working directory changed, restart in the
        // new location so the header and the shell agree on where you are.
        if dir != ToolBinary.usableDirectory(currentContext.workingDirectory) {
            currentContext = context
            session.restart(makeLaunch(dir: dir))
            session.focusTerminal()
        }
        // Context subject change only (service name, not directory) — the shell
        // is unaffected and the focus stays where it is.
        currentContext = context
    }

    func resize(to grid: TerminalGrid) {
        session.settle(grid)
    }

    func deactivate() {
        // Leave the session warm. The running indicator clears because `isLive`
        // stays true, but the chevron in the chrome closes the panel — the shell
        // is still there.
    }

    func makeView() -> AnyView {
        AnyView(
            PTYPanelView(
                session: session,
                tooNarrowDetail: "A shell needs at least \(TerminalGrid.minimum.columns) columns "
                    + "and \(TerminalGrid.minimum.rows) rows to draw honestly. Widen the panel."
            )
            .onAppear {
                // The panel was just revealed. If a grid was already settled
                // (e.g. resized while hidden), flush it now.
                if let grid = self.session.proposed {
                    self.session.settle(grid)
                }
                self.session.focusTerminal()
            }
        )
    }

    // MARK: Private

    private func makeLaunch(dir: URL) -> PTYSession.Launch {
        PTYSession.Launch(
            executable: ToolBinary.loginShell,
            arguments: [],
            // A leading dash tells the shell it is a login shell, so it reads
            // ~/.zprofile / ~/.bash_profile and picks up $PATH, aliases and
            // other interactive setup the user expects.
            argv0: "-" + ToolBinary.loginShell.lastPathComponent,
            workingDirectory: dir,
            environment: ToolBinary.environment(withSearchPath: false)
        )
    }
}
