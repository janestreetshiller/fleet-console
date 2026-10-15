import SwiftUI
import Foundation
import Observation

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

@Observable
@MainActor
final class TerminalPanel: PTYBackedSurface {
    let tool: ConsoleTool = .terminal

    private let shellSession = PTYSession(refusesBelowMinimum: false)
    private var investigationSession: PTYSession?
    private var session: PTYSession { investigationSession ?? shellSession }

    private var investigationBusy = false
    private var investigationBilling: OurosBilling?
    @ObservationIgnored private var investigationTask: Task<Void, Never>?

    /// Separate output-only terminal transcript. Never creates a local inference
    /// process, types into a shell, or exposes the account token to argv/env.
    func investigate(_ starter: String, billing: OurosBilling, validation: @escaping @MainActor () -> Bool) -> Bool {
        guard !investigationBusy else { return false }
        let fresh = PTYSession(refusesBelowMinimum: false)
        if let grid = session.proposed { fresh.settle(grid) }
        investigationSession = fresh
        investigationBilling = billing
        investigationBusy = true
        appendInvestigation(starter + "\n\nVerifying Ouros agent availability…\n")
        investigationTask = Task { [weak self] in
            guard let self else { return }
            defer { investigationBusy = false; investigationTask = nil }
            do {
                let reply = try await billing.investigate(starter: starter, validateObservation: validation)
                appendInvestigation("\nOuros analysis (snapshot only; no execution tools):\n" + reply + "\n")
            } catch { appendInvestigation("\n" + error.localizedDescription + "\n") }
        }
        fresh.focusTerminal()
        return true
    }

    private func appendInvestigation(_ text: String) {
        // Provider output is untrusted: strip terminal escape/control sequences
        // and directional overrides before feeding the emulator as display data.
        let safe = String(text.unicodeScalars.filter {
            $0 == "\n" || $0 == "\t" || (!CharacterSet.controlCharacters.contains($0)
                && !(0x202A...0x202E).contains($0.value) && !(0x2066...0x2069).contains($0.value))
        })
        investigationSession?.host.terminal.feed(text: safe.replacingOccurrences(of: "\n", with: "\r\n"))
    }
    private var currentContext = ToolContext()
    private var activated = false

    // MARK: PTYBackedSurface

    var cellMetrics: TerminalCellMetrics { session.cell }

    var reservedWidth: CGFloat { session.reservedWidth }

    var isLive: Bool { investigationBusy || shellSession.phase == .running }

    // MARK: ToolSurface

    func activate(context: ToolContext) {
        if investigationSession != nil { session.focusTerminal(); return }
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
            VStack(spacing: 4) {
            if investigationSession != nil {
                HStack {
                    Text("Read-only investigation").font(ConsoleFont.caption)
                    Spacer()
                    Button("Return to shell") {
                        investigationSession = nil
                        activate(context: currentContext)
                    }
                        .disabled(investigationBusy)
                }
                if let billing = investigationBilling, let requestID = billing.unconfirmedInvestigationID, !investigationBusy {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unconfirmed request: " + requestID).font(ConsoleFont.caption).textSelection(.enabled)
                        Button("Acknowledge after reviewing account receipts") { billing.acknowledgeUnconfirmedInvestigation() }
                    }
                }
            }
            PTYPanelView(
                session: session,
                tooNarrowDetail: "A shell needs at least \(TerminalGrid.minimum.columns) columns "
                    + "and \(TerminalGrid.minimum.rows) rows to draw honestly. Widen the panel."
            )
            .id(ObjectIdentifier(session.host))
            .onAppear {
                // The panel was just revealed. If a grid was already settled
                // (e.g. resized while hidden), flush it now.
                if let grid = self.session.proposed {
                    self.session.settle(grid)
                }
                self.session.focusTerminal()
            }
            }
        )
    }

    /// Runs one command line in the panel's shell, as if typed and entered.
    @discardableResult
    func run(_ commandLine: String) -> Bool {
        guard investigationSession == nil else { return false }
        session.send(commandLine + "\r")
        session.focusTerminal()
        return true
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
