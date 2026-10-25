import AppKit
import SwiftUI
import Vision
import Testing
import FleetCore
@testable import FleetConsoleApp

@Suite(.serialized)
struct TerminalAgentSessionTests {
    @MainActor @Test("Agent handoffs use fixed argv, never shell interpolation")
    func fixedArguments() {
        let prompt = "do not execute $(touch /tmp/fleet-unwanted); 'quotes'\nnext line"
        for kind in FixAgentKind.allCases {
            let request = request(kind: kind, executable: URL(fileURLWithPath: "/agent's path/tool"), prompt: prompt)
            let launch = request.launch
            #expect(launch.executable.path == "/agent's path/tool")
            #expect(launch.argv0 == nil)
            if kind == .fleetAgent {
                #expect(launch.arguments == ["propose", "--prompt-file", request.reportURL.path])
                #expect(!launch.arguments.contains(prompt))
            } else { #expect(launch.arguments == [prompt]) }
            #expect(launch.environment.contains { $0.hasPrefix("PATH=") })
        }
    }

    @MainActor @Test("A deferred PTY launch and buffered input are cancelled before any child starts")
    func cancelDeferredLaunch() {
        let session = PTYSession(refusesBelowMinimum: false)
        session.ensureRunning(PTYSession.Launch(executable: URL(fileURLWithPath: "/bin/cat"),
            workingDirectory: FileManager.default.temporaryDirectory, environment: []))
        session.send("must not replay\n")
        session.terminate()
        session.settle(TerminalGrid(columns: 40, rows: 10))
        #expect(session.phase == .exited(nil))
        #expect(session.launch == nil)
        #expect(session.host.terminal.process.running == false)
    }

    @MainActor @Test("Session capacity refuses new work, retains old PTYs and permits closing deferred sessions")
    func boundedSessions() throws {
        let panel = TerminalPanel()
        for _ in 0..<TerminalPanel.maximumAgentSessions {
            #expect(panel.startAgent(request()))
        }
        let IDs = panel.agents.map(\.id)
        #expect(!panel.startAgent(request()))
        #expect(panel.agents.map(\.id) == IDs)
        #expect(!panel.run("echo must-not-enter-agent"))
        #expect(panel.closeSelectedAgent())
        #expect(panel.agents.count == TerminalPanel.maximumAgentSessions - 1)
        #expect(panel.startAgent(request()))
        #expect(!panel.startAgent(request(executable: URL(fileURLWithPath: "/no-such-fleet-agent"))))
        panel.agents.forEach { $0.pty.terminate() }
    }

    @MainActor @Test("Exit status never claims a successful repair")
    func statusIsEvidenceOnly() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = try script("#!/bin/sh\nprintf 'TEST-EXIT\\n'\nexit 7\n", directory: directory)
        let panel = TerminalPanel()
        #expect(panel.startAgent(request(executable: executable)))
        let agent = try #require(panel.selectedAgent)
        #expect(agent.status == "Waiting for terminal layout")
        panel.resize(to: TerminalGrid(columns: 60, rows: 16))
        try await waitUntil { if case .exited = agent.pty.phase { return true }; return false }
        #expect(agent.status == "Exited 7 · review output")
        #expect(!agent.status.contains("fixed"))
        #expect(agent.policy.contains("external agent"))
    }

    @MainActor @Test("Real PTYs isolate agent argv, working directory, shell and simultaneous sessions")
    func realSessionIsolation() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = try script("""
        #!/bin/sh
        printf 'AGENT-ARG:%s\\n' "$1"
        printf 'AGENT-CWD:%s\\n' "$PWD"
        while IFS= read -r line; do
          printf 'AGENT-INPUT:%s\\n' "$line"
        done
        """, directory: directory)
        let panel = TerminalPanel()
        let size = CGSize(width: 500, height: 440)
        let hosting = NSHostingView(rootView: panel.makeView().frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderBack(nil)
        defer {
            panel.agents.forEach { $0.pty.terminate() }
            window.close()
        }
        panel.resize(to: TerminalGrid(columns: 60, rows: 18))
        panel.activate(context: ToolContext(workingDirectory: directory, subject: "fixture shell"))
        try await waitUntil { findHost(in: hosting)?.terminal.process.running == true }
        let shellHost = try #require(findHost(in: hosting))
        let shellPID = shellHost.terminal.process.shellPid
        #expect(panel.run("printf 'SHELL-ALIVE\\n'"))
        try await waitUntil { text(shellHost).contains("SHELL-ALIVE") }

        let prompt = "literal $(printf UNWANTED) 'quoted'"
        #expect(panel.startAgent(request(executable: executable, prompt: prompt, directory: directory)))
        panel.resize(to: TerminalGrid(columns: 60, rows: 18))
        let first = try #require(panel.selectedAgent)
        try await waitUntil { text(first.pty.host).contains("AGENT-ARG:" + prompt) }
        #expect(text(first.pty.host).contains("AGENT-CWD:"))
        #expect(text(first.pty.host).contains("/" + directory.lastPathComponent))
        #expect(!panel.run("printf INJECTED"))
        #expect(!panel.closeSelectedAgent(), "Running sessions require explicit stop before removal")
        let firstPID = first.pty.host.terminal.process.shellPid

        #expect(panel.startAgent(request(executable: executable, prompt: "second", directory: directory)))
        panel.resize(to: TerminalGrid(columns: 60, rows: 18))
        let second = try #require(panel.selectedAgent)
        try await waitUntil { text(second.pty.host).contains("AGENT-ARG:second") }
        #expect(firstPID != second.pty.host.terminal.process.shellPid)
        panel.select(.agent(first.id))
        #expect(first.pty.host.terminal.process.shellPid == firstPID)
        panel.activate(context: ToolContext(workingDirectory: URL(fileURLWithPath: "/"), subject: "unrelated selection"))
        #expect(first.pty.host.terminal.process.shellPid == firstPID)
        #expect(first.pty.launch?.workingDirectory == directory)
        panel.deactivate()
        #expect(first.pty.phase == .running)

        panel.select(.shell)
        #expect(shellHost.terminal.process.shellPid == shellPID)
        #expect(panel.run("printf 'SHELL-STILL-ALIVE\\n'"))
        try await waitUntil { text(shellHost).contains("SHELL-STILL-ALIVE") }
        #expect(!text(first.pty.host).contains("SHELL-STILL-ALIVE"))
        #expect(!text(first.pty.host).contains("INJECTED"))
        panel.select(.agent(first.id))
        panel.stopSelectedAgent()
        #expect(first.pty.phase == .stopping)
        #expect(!panel.closeSelectedAgent())
        try await waitUntil { first.pty.phase == .exited(nil) }
        #expect(second.pty.phase == .running)
        #expect(shellHost.terminal.process.running)
        #expect(panel.closeSelectedAgent())
        #expect(panel.selection == .shell)
        #expect(panel.agents.map(\.id) == [second.id])

        // Closing the owned window terminates its shell. Same-directory reopen must recover.
        window.close()
        panel.windowReopened()
        try await waitUntil { shellHost.terminal.process.running }
        #expect(shellHost.terminal.process.shellPid != shellPID)
    }

    @MainActor @Test("A new external TUI cannot inherit the previous surface grid or launch below its minimum")
    func freshAgentWaitsForItsOwnGrid() throws {
        let panel = TerminalPanel()
        panel.resize(to: TerminalGrid(columns: 80, rows: 30))
        #expect(panel.startAgent(request()))
        let agent = try #require(panel.selectedAgent)
        #expect(agent.pty.phase == .idle)
        #expect(agent.pty.proposed == nil)
        panel.resize(to: TerminalGrid(columns: 20, rows: 4))
        #expect(agent.pty.phase == .idle)
        #expect(agent.pty.isTooNarrow)
        panel.windowClosed()
        panel.resize(to: TerminalGrid(columns: 80, rows: 30))
        #expect(!agent.pty.host.terminal.process.running)
    }

    @MainActor @Test("A fresh session receives a grid even when the destination matches the last settled layout")
    func sameGridCanBeReissuedForFreshSession() throws {
        let tools = ChromeTools()
        tools.toggle(.terminal, context: ToolContext())
        defer { tools.registry.closeTerminalSessions() }
        let size = CGSize(width: 500, height: 400)
        tools.propose(size: size)
        tools.flushGeometry()
        #expect(tools.startAgent(request()))
        let panel = try #require(tools.registry.surface(for: .terminal) as? TerminalPanel)
        let agent = try #require(panel.selectedAgent)
        tools.propose(size: size)
        tools.flushGeometry()
        #expect(agent.pty.launch == nil)
        // Production invokes this on the newly measured header's layoutRevision.
        tools.invalidateGeometry()
        tools.flushGeometry()
        #expect(agent.pty.launch != nil)
    }

    @MainActor @Test("Stopping reaps stubborn children in the app-owned group before allowing Close")
    func processGroupCleanup() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = try script("""
        #!/bin/sh
        trap '' TERM HUP
        /bin/sh -c 'trap "" TERM HUP; while :; do sleep 1; done' &
        printf 'DESCENDANT:%s\\n' "$!"
        wait
        """, directory: directory)
        let panel = TerminalPanel()
        #expect(panel.startAgent(request(executable: executable)))
        panel.resize(to: TerminalGrid(columns: 60, rows: 18))
        let agent = try #require(panel.selectedAgent)
        try await waitUntil { text(agent.pty.host).contains("DESCENDANT:") }
        let output = text(agent.pty.host)
        let digits = try #require(output.components(separatedBy: "DESCENDANT:").last?.prefix(while: { $0.isNumber }))
        let childPID = try #require(Int32(digits))
        #expect(kill(childPID, 0) == 0)
        panel.stopSelectedAgent()
        #expect(agent.pty.phase == .stopping)
        #expect(!panel.closeSelectedAgent())
        try await waitUntil { agent.pty.phase == .exited(nil) }
        // A dead grandchild can briefly remain a zombie until launchd reaps it.
        try await waitUntil { kill(childPID, 0) != 0 }
        #expect(panel.closeSelectedAgent())
        panel.windowClosed()
    }

    @MainActor @Test("Measured terminal controls are removed from the coalesced row budget")
    func terminalChromeGeometry() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        let tools = ChromeTools()
        let panel = try #require(tools.registry.surface(for: .terminal) as? TerminalPanel)
        tools.toggle(.terminal, context: ToolContext())
        let size = CGSize(width: 420, height: 340)
        let hosting = NSHostingView(rootView: panel.makeView().frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderBack(nil)
        defer { window.close() }
        try await waitUntil { panel.chromeHeight > 0 }
        tools.propose(size: size)
        tools.flushGeometry()
        let grid = try #require(tools.settledGrid)
        #expect(CGFloat(grid.rows) * panel.cellMetrics.height <= size.height - panel.chromeHeight)
        #expect(grid.rows < TerminalGrid.fitting(size, cell: panel.cellMetrics, reservedWidth: panel.reservedWidth).rows)
    }

    @MainActor @Test("Window close cancels never-displayed sessions and cannot resurrect deferred agents")
    func windowCloseCancelsHiddenSessions() throws {
        let registry = ToolSurfaceRegistry()
        let panel = try #require(registry.surface(for: .terminal) as? TerminalPanel)
        #expect(panel.startAgent(request()))
        #expect(panel.startAgent(request()))
        let agents = panel.agents
        registry.closeTerminalSessions()
        #expect(agents.allSatisfy { $0.pty.phase == .exited(nil) })
        panel.select(.agent(agents[0].id))
        panel.resize(to: TerminalGrid(columns: 60, rows: 18))
        #expect(agents.allSatisfy { !$0.pty.host.terminal.process.running })
        #expect(agents.allSatisfy { $0.pty.launch == nil })
    }

    @MainActor @Test("Agent surface fits narrow and wide layouts in light and dark", arguments: [false, true], [CGFloat(320), CGFloat(600)])
    func nativeSurface(dark: Bool, width: CGFloat) async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = try script("#!/bin/sh\nprintf 'Proposal: inspect the failed check\\nNo changes executed.\\n'\nexit 0\n", directory: directory)
        let panel = TerminalPanel()
        let suggestion = TroubleshootingSuggestion(id: "health-fixture", title: "API: health check failing",
            evidence: "Three recorded failures; process presence is not a health result.",
            checks: ["Compare the configured health target with the latest result."],
            remedies: ["Review dependencies before approving a controller restart."], occurrences: 3)
        let handoff = TerminalAgentRequest(kind: .fleetAgent, executable: executable, prompt: "fixture",
            reportURL: directory.appendingPathComponent("request.md"), workingDirectory: directory,
            subject: "API health check", suggestions: [suggestion])
        #expect(panel.startAgent(handoff))
        let agent = try #require(panel.selectedAgent)
        let size = CGSize(width: width, height: 340)
        let hosting = NSHostingView(rootView: panel.makeView().frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.orderFront(nil)
        defer { panel.windowClosed(); window.close() }
        try await waitUntil { panel.chromeHeight > 0 }
        panel.resize(to: TerminalGrid.fitting(CGSize(width: width, height: size.height - panel.chromeHeight),
                                            cell: panel.cellMetrics, reservedWidth: panel.reservedWidth))
        try await waitUntil { if case .exited = agent.pty.phase { return true }; return false }
        #expect(agent.status == "Exited 0 · review output")
        #expect(text(agent.pty.host).contains("No changes executed."))
        // Keyboard focus lands on the actual emulator, not a hidden shell.
        panel.select(.agent(agent.id))
        #expect(window.firstResponder === agent.pty.host.terminal)
        let name = "agent-session-\(Int(width))-\(dark ? "dark" : "light")"
        let rendered = try capture(hosting, name: name)
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: try #require(rendered.cgImage)).perform([recognition])
        let visible = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        #expect(visible.contains("Exited 0"), "The rendered lifecycle label must follow the real PTY phase")
        #expect(!visible.contains("Waiting for terminal layout"))
        window.contentView = NSHostingView(rootView: panel.agentDetails)
        window.setContentSize(CGSize(width: 377, height: 377))
        try await Task.sleep(for: .milliseconds(80))
        try capture(try #require(window.contentView), name: name + "-details")
    }

    @discardableResult
    @MainActor private func capture(_ view: NSView, name: String) throws -> NSBitmapImageRep {
        for _ in 0..<8 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.025))
        }
        let canvas = view.window?.contentView?.superview ?? view
        canvas.layoutSubtreeIfNeeded()
        let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        bitmap.size = canvas.bounds.size
        canvas.setNeedsDisplay(canvas.bounds)
        view.window?.displayIfNeeded()
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        if let path = ProcessInfo.processInfo.environment["FLEET_AGENT_SESSION_EVIDENCE_DIR"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent(name + ".png"))
        }
        return bitmap
    }

    private func request(kind: FixAgentKind = .codex, executable: URL = URL(fileURLWithPath: "/bin/cat"),
                         prompt: String = "fixture", directory: URL = FileManager.default.temporaryDirectory) -> TerminalAgentRequest {
        TerminalAgentRequest(kind: kind, executable: executable, prompt: prompt,
            reportURL: directory.appendingPathComponent("request.md"), workingDirectory: directory,
            subject: "Test request", suggestions: [])
    }

    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fleet agent's test " + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.resolvingSymlinksInPath()
    }

    private func script(_ contents: String, directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("agent's fixture")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    @MainActor private func findHost(in view: NSView) -> PTYHostView? {
        (view as? PTYHostView) ?? view.subviews.lazy.compactMap { findHost(in: $0) }.first
    }

    @MainActor private func text(_ host: PTYHostView) -> String {
        let terminal = host.terminal.getTerminal()
        return (0..<terminal.rows).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) }.joined()
    }

    @MainActor private func waitUntil(_ predicate: () -> Bool) async throws {
        // Other native suites share AppKit's main actor and can hold it for
        // several seconds while capturing/OCRing views during a full test run.
        let deadline = Date().addingTimeInterval(20)
        while !predicate() {
            guard Date() < deadline else { throw NSError(domain: "TerminalAgentSessionTests.timeout", code: 1) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
