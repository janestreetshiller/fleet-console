import SwiftUI
import Foundation
import Observation

/// A warm shell, bounded dedicated agent PTYs and a separate output-only investigation.
/// Agent launches never type into a shell or a previously running interactive agent.
@Observable
@MainActor
final class TerminalPanel: PTYBackedSurface {
    let tool: ConsoleTool = .terminal
    static let maximumAgentSessions = 4

    enum Selection: Hashable {
        case shell
        case agent(UUID)
        case investigation
    }

    private let shellSession = PTYSession(refusesBelowMinimum: false)
    private var investigationSession: PTYSession?
    private(set) var agents: [TerminalAgentSession] = []
    private(set) var selection: Selection = .shell {
        didSet { confirmingStop = false; showingDetails = false }
    }
    private(set) var chromeHeight: CGFloat = 0
    private(set) var layoutRevision = 0
    private var session: PTYSession {
        if selection == .investigation, let investigationSession { return investigationSession }
        return selectedAgent?.pty ?? shellSession
    }
    var selectedAgent: TerminalAgentSession? {
        guard case .agent(let id) = selection else { return nil }
        return agents.first { $0.id == id }
    }

    private(set) var investigationBusy = false
    private var investigationBilling: OurosBilling?
    private var investigationCancelling = false
    @ObservationIgnored private var investigationTask: Task<Void, Never>?
    private var currentContext = ToolContext()
    private var activated = false
    private var lastGrid: TerminalGrid?
    private var showingDetails = false
    private var confirmingStop = false

    /// Starting is an explicit operator handoff. Refuse before touching any live PTY.
    @discardableResult
    func startAgent(_ request: TerminalAgentRequest) -> Bool {
        guard agents.count < Self.maximumAgentSessions,
              FileManager.default.isExecutableFile(atPath: request.executable.path) else { return false }
        let agent = TerminalAgentSession(request: request)
        agents.append(agent)
        selection = .agent(agent.id)
        // The destination header must be measured before this fresh PTY inherits a grid.
        agent.pty.ensureRunning(request.launch)
        agent.pty.focusTerminal()
        return true
    }

    func select(_ value: Selection) {
        switch value {
        case .shell: break
        case .agent(let id): guard agents.contains(where: { $0.id == id }) else { return }
        case .investigation: guard investigationSession != nil else { return }
        }
        selection = value
        if value == .shell { activate(context: currentContext) }
        if let lastGrid { session.settle(lastGrid) }
        session.focusTerminal()
    }

    /// Only the app-owned foreground agent child is stopped, never a managed service.
    func stopSelectedAgent() {
        guard let id = selectedAgent?.id else { return }
        stopAgent(id: id)
    }

    private func stopAgent(id: UUID) {
        agents.first { $0.id == id }?.stop()
    }

    @discardableResult
    func closeSelectedAgent() -> Bool {
        guard let agent = selectedAgent, agent.pty.phase != .running, agent.pty.phase != .stopping else { return false }
        agent.pty.terminate() // Also cancels a launch still waiting for geometry.
        agents.removeAll { $0.id == agent.id }
        select(.shell)
        return true
    }

    /// Account-funded requests stay output-only; neither output nor tokens enter a PTY child.
    func investigate(_ starter: String, billing: OurosBilling, validation: @escaping @MainActor () -> Bool) -> Bool {
        guard !investigationBusy else { return false }
        let fresh = PTYSession(refusesBelowMinimum: false)
        if let lastGrid { fresh.settle(lastGrid) }
        investigationSession = fresh
        selection = .investigation
        investigationBilling = billing
        investigationBusy = true
        appendInvestigation(starter + "\n\nVerifying Ouros agent availability…\n")
        investigationTask = Task { [weak self] in
            guard let self else { return }
            defer { investigationBusy = false; investigationCancelling = false; investigationTask = nil }
            do {
                let reply = try await billing.investigate(starter: starter, validateObservation: validation)
                appendInvestigation("\nOuros analysis (snapshot only; no execution tools):\n" + reply + "\n")
            } catch { appendInvestigation("\n" + error.localizedDescription + "\n") }
        }
        fresh.focusTerminal()
        return true
    }

    func cancelInvestigation() {
        guard investigationBusy else { return }
        investigationCancelling = true
        investigationTask?.cancel()
    }

    private func appendInvestigation(_ text: String) {
        let safe = String(text.unicodeScalars.filter {
            $0 == "\n" || $0 == "\t" || (!CharacterSet.controlCharacters.contains($0)
                && !(0x202A...0x202E).contains($0.value) && !(0x2066...0x2069).contains($0.value))
        })
        investigationSession?.host.terminal.feed(text: safe.replacingOccurrences(of: "\n", with: "\r\n"))
    }

    var cellMetrics: TerminalCellMetrics { session.cell }
    var reservedWidth: CGFloat { session.reservedWidth }
    var isLive: Bool {
        investigationBusy || shellSession.phase == .running || shellSession.phase == .stopping
            || agents.contains { $0.pty.phase == .running || $0.pty.phase == .stopping }
    }

    func activate(context: ToolContext) {
        // Selection/navigation cannot retarget or kill an agent or the background shell.
        guard selection == .shell else { session.focusTerminal(); return }
        let dir = ToolBinary.usableDirectory(context.workingDirectory)
        if !activated {
            currentContext = context
            activated = true
            shellSession.ensureRunning(makeLaunch(dir: dir))
            shellSession.focusTerminal()
            return
        }
        if dir != ToolBinary.usableDirectory(currentContext.workingDirectory) {
            shellSession.restart(makeLaunch(dir: dir))
            shellSession.focusTerminal()
        } else {
            // Reopen after a window close or shell exit, preserving the old scrollback.
            shellSession.ensureRunning(makeLaunch(dir: dir))
        }
        currentContext = context
    }

    func resize(to grid: TerminalGrid) {
        lastGrid = grid
        session.settle(grid)
    }

    func deactivate() {} // Warm PTYs survive a panel toggle, not a window close.

    func windowReopened() {
        if selection == .shell { activate(context: currentContext) }
        else { session.focusTerminal() } // Ended agents never rerun automatically.
    }

    func windowClosed() {
        // Include never-displayed and deferred sessions, whose host has no window observer yet.
        shellSession.terminate()
        agents.forEach { $0.stop() }
        cancelInvestigation() // Keep any dispatched operation identity; never replay it.
    }

    func makeView() -> AnyView {
        AnyView(TerminalSurfaceView(panel: self))
    }

    fileprivate var surfaceView: some View {
        VStack(spacing: 4) {
            controls
                .background {
                    GeometryReader { geometry in
                        Color.clear.onAppear { self.measuredChrome(geometry.size.height + 4) }
                            .onChange(of: geometry.size.height) { _, height in self.measuredChrome(height + 4) }
                    }
                }
                .id(selection)
            PTYPanelView(session: session, tooNarrowDetail: "Widen the terminal panel.")
                .id(ObjectIdentifier(session.host))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    if self.session.phase != .idle, let lastGrid = self.lastGrid { self.session.settle(lastGrid) }
                    self.session.focusTerminal()
                }
        }
    }

    private func measuredChrome(_ height: CGFloat) {
        chromeHeight = height
        // A new PTY needs an emission even when its grid equals the previously
        // settled one (including a rapid switch that cancels an intervening resize).
        layoutRevision += 1
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Picker("Session", selection: Binding(get: { self.selection }, set: { self.select($0) })) {
                    Text("Shell").tag(Selection.shell)
                    ForEach(agents) { agent in
                        Text(agent.request.kind.title + " · " + agent.request.subject).tag(Selection.agent(agent.id))
                    }
                    if investigationSession != nil { Text("Ouros investigation").tag(Selection.investigation) }
                }
                .labelsHidden()
                .accessibilityLabel("Terminal session")
                .frame(maxWidth: .infinity)
                if selectedAgent != nil {
                    Button("Details") { self.showingDetails.toggle() }
                        .popover(isPresented: Binding(get: { self.showingDetails }, set: { self.showingDetails = $0 })) {
                            self.agentDetails
                        }
                }
            }
            if let agent = selectedAgent {
                HStack {
                    Text(agent.status).lineLimit(1).help(agent.status)
                    Spacer(minLength: 0)
                    if agent.pty.phase == .running {
                        Button("Stop…") { self.confirmingStop = true }
                            .confirmationDialog("Stop this agent session?", isPresented: Binding(
                                get: { self.confirmingStop }, set: { self.confirmingStop = $0 })) {
                                Button("Stop agent", role: .destructive) { self.stopAgent(id: agent.id) }
                            } message: {
                                Text("Stops this app-owned terminal process group. It does not stop controller-managed services or undo work. Provider billing may still apply.")
                            }
                    } else if agent.pty.phase != .stopping {
                        Button("Close session") { _ = self.closeSelectedAgent() }
                    }
                }
            } else if selection == .investigation {
                Text(investigationBusy ? "Read-only investigation · awaiting account response" : "Read-only investigation · review output")
                if investigationBusy {
                    Button(investigationCancelling ? "Stopping…" : "Stop waiting") { self.cancelInvestigation() }
                        .disabled(investigationCancelling)
                        .help("Cancels waiting, not confirmed provider usage. Review any unconfirmed account receipt before retrying.")
                }
                if let billing = investigationBilling, let requestID = billing.unconfirmedInvestigationID, !investigationBusy {
                    Text("Unconfirmed request: " + requestID).textSelection(.enabled)
                    Button("Acknowledge after reviewing account receipts") { billing.acknowledgeUnconfirmedInvestigation() }
                }
            } else if case .exited = shellSession.phase {
                Button("Restart shell") { self.activate(context: self.currentContext) }
            }
        }
        .font(ConsoleFont.caption)
    }

    /// Shared with native surface acceptance tests; the popover renders this exact view.
    var agentDetails: some View {
        ScrollView {
            if let agent = selectedAgent {
                VStack(alignment: .leading, spacing: 8) {
                    Text(agent.request.kind.title).font(ConsoleFont.body.weight(.semibold))
                    Text(agent.policy)
                    Text(agent.request.subject)
                    Text("Started \(agent.createdAt.formatted())")
                    Text("Directory: " + (agent.pty.launch?.workingDirectory ?? agent.request.workingDirectory).path).textSelection(.enabled)
                    Text("Report: " + agent.request.reportURL.path).textSelection(.enabled)
                    Button("Reveal saved request") { NSWorkspace.shared.activateFileViewerSelecting([agent.request.reportURL]) }
                    Text("Troubleshooting suggestions").font(ConsoleFont.body.weight(.semibold))
                    Text("Ranked by matching events observed locally in the last six hours, not population statistics. Snapshot only; verify current evidence before acting.")
                    if agent.request.suggestions.isEmpty {
                        Text("No supported problem pattern matched this request. Review the saved findings with the agent.")
                    }
                    ForEach(agent.request.suggestions) { suggestion in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.title).font(ConsoleFont.body.weight(.semibold))
                            Text(suggestion.evidence)
                            Text("Matching recent events: \(suggestion.occurrences)")
                            ForEach(Array(suggestion.checks.enumerated()), id: \.offset) { _, check in Text("Check: " + check) }
                            ForEach(Array(suggestion.remedies.enumerated()), id: \.offset) { _, remedy in Text("Option: " + remedy) }
                        }
                    }
                }
                .font(ConsoleFont.caption)
                .padding(ConsoleMetrics.cardPadding)
                .textSelection(.enabled)
            }
        }
        .frame(width: ConsoleToolMetrics.panelIdeal, height: ConsoleToolMetrics.panelIdeal)
    }

    /// Generic commands are accepted only in Shell; never inject them into an agent TUI.
    @discardableResult
    func run(_ commandLine: String) -> Bool {
        guard selection == .shell else { return false }
        shellSession.ensureRunning(makeLaunch(dir: ToolBinary.usableDirectory(currentContext.workingDirectory)))
        shellSession.send(commandLine + "\r")
        shellSession.focusTerminal()
        return true
    }

    private func makeLaunch(dir: URL) -> PTYSession.Launch {
        PTYSession.Launch(executable: ToolBinary.loginShell, arguments: [],
                         argv0: "-" + ToolBinary.loginShell.lastPathComponent,
                         workingDirectory: dir, environment: ToolBinary.environment(withSearchPath: false))
    }
}

/// Observation must happen in a SwiftUI body, not once when makeView constructs an AnyView.
private struct TerminalSurfaceView: View {
    @Bindable var panel: TerminalPanel

    var body: some View { panel.surfaceView }
}
