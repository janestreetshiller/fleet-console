import AppKit
import SwiftUI
import SwiftTerm
import Testing
@testable import FleetConsoleApp

@Suite(.serialized)
struct TerminalOutputTests {
    @MainActor
    @Test("Production proposal formatter fixtures render through the actual shell PTY",
          .enabled(if: ProcessInfo.processInfo.environment["FLEET_TERMINAL_FORMATTER_FIXTURES"] != nil
            || ProcessInfo.processInfo.environment["FLEET_AGENT_PRESENTATION_EVIDENCE_DIR"] != nil))
    func actualFormatterFixtures() async throws {
        let environment = ProcessInfo.processInfo.environment
        let fixturePath = try #require(environment["FLEET_TERMINAL_FORMATTER_FIXTURES"]
            ?? environment["FLEET_AGENT_PRESENTATION_EVIDENCE_DIR"])
        let fixtures = URL(fileURLWithPath: fixturePath, isDirectory: true)
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.finishLaunching()
        let panel = TerminalPanel()
        let grid = TerminalGrid(columns: 56, rows: 28)
        let size = CGSize(width: panel.cellMetrics.width * CGFloat(grid.columns) + panel.reservedWidth + 0.5,
                          height: panel.cellMetrics.height * CGFloat(grid.rows) + 0.5)
        let hosting = NSHostingView(rootView: panel.makeView().frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.orderBack(nil)
        defer { window.close() }
        panel.resize(to: grid)
        panel.activate(context: ToolContext())
        try await settle(0.15)
        let terminal = try #require(findHost(in: hosting)).terminal
        panel.run("stty -echo; if [ -n \"$ZSH_VERSION\" ]; then unsetopt zle; fi; PS1=''; PS2=''; RPROMPT=''; printf '\\033[2J\\033[HFORMATTER-READY\\n'")
        try await waitFor(terminal, containing: "FORMATTER-READY")
        var outputs: [String: String] = [:]
        for name in ["short", "wrapped", "controls", "error"] {
            let path = fixtures.appendingPathComponent(name + ".ansi")
            let raw = try String(contentsOf: path, encoding: .utf8)
            try #require(raw.contains("TEST DATA:"), "Source formatter fixtures must identify their test content.")
            window.appearance = NSAppearance(named: .darkAqua)
            panel.run("printf '\\033[2J\\033[H'; /bin/cat " + shellQuote(path.path)
                + "; printf '\\nFORMATTER-DONE:" + name + "\\n'")
            try await waitFor(terminal, containing: "FORMATTER-DONE:" + name)
            let output = selectedText(terminal)
            outputs[name] = output
            terminal.selectNone()
            _ = try capture(terminal, name: "formatter-fixture-" + name + "-dark")
            window.appearance = NSAppearance(named: .aqua)
            try await settle(0.15)
            _ = try capture(terminal, name: "formatter-fixture-" + name + "-light")
            let snapshot = try #require(terminal.terminalContentSnapshot(region: .viewport))
            let heading = name == "error" ? "Error" : "Proposal"
            let row = try #require(snapshot.rows.first { $0.text == heading })
            #expect(row.cells[0].attribute.style.contains(.bold) == true)
            #expect(!output.contains("\u{1b}"), "Selection exposes readable text, not ANSI bytes.")
            switch name {
            case "short":
                #expect(output.contains("TEST DATA: A short read-only proposal for formatter/PTY verification."))
                #expect(output.contains("Preparing proposal"))
            case "wrapped":
                let paragraph = String(repeating: "Evidence, command, result and status remain readable with every original word preserved. ", count: 5)
                #expect(output.contains(paragraph.trimmingCharacters(in: .whitespaces)))
                #expect(output.contains("    Indented evidence stays indented."))
                #expect(output.contains("/a/long/path/whose/full/content/must/stay/copyable/without/truncation"))
            case "controls":
                #expect(output.contains("red content"))
                #expect(output.contains("Progress 90%"))
                #expect(!output.contains("Progress 10%"))
                #expect(output.contains("Unicode 世界 · café"))
                #expect(output.contains("\n\nOriginal blank line above."))
            case "error":
                #expect(output.contains("fleet-agent: TEST DATA: Failed command\n  Full detail: permission denied for /a/long/path; diagnostic E42 stays intact."))
            default: break
            }
        }
        if let directory = evidenceDirectory {
            let receipt: [String: Any] = [
                "entryPoint": "production Rust ProposalPresentation output files -> TerminalPanel.run /bin/cat -> real PTY -> SwiftTerm",
                "fixtureDirectory": fixturePath,
                "fixtureDisplay": true,
                "modelInference": false,
                "desktopInteraction": false,
                "selectedOutput": outputs
            ]
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("formatter-fixture-receipt.json"))
        }
    }

    @MainActor
    @Test("Actual fleet-agent proposal renders a deterministic HTTP response",
          .enabled(if: ProcessInfo.processInfo.environment["FLEET_TERMINAL_LLM_URL"] != nil))
    func actualAgentProposal() async throws {
        let environment = ProcessInfo.processInfo.environment
        let binary = try #require(environment["FLEET_TERMINAL_AGENT_BINARY"])
        let endpoint = try #require(environment["FLEET_TERMINAL_LLM_URL"])
        try #require(FileManager.default.isExecutableFile(atPath: binary))
        let url = try #require(URL(string: endpoint))
        try #require(url.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(url.host ?? ""),
                     "The rendering fixture must be served by an owned loopback HTTP endpoint.")
        let styled = environment["FLEET_TERMINAL_EXPECT_AGENT_STYLE"] == "1"
        let expectedReply = environment["FLEET_TERMINAL_EXPECTED_REPLY"]
            ?? "Finding: 3 services healthy.\n\nEvidence: deterministic HTTP fixture.\n\nProposed action: none."
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prompt = "Explain the deterministic terminal rendering verification response."
        let promptFile = directory.appendingPathComponent("question.txt")
        try Data(prompt.utf8).write(to: promptFile)

        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.finishLaunching()
        let panel = TerminalPanel()
        let grid = TerminalGrid(columns: 56, rows: 22)
        let size = CGSize(width: panel.cellMetrics.width * CGFloat(grid.columns) + panel.reservedWidth + 0.5,
                          height: panel.cellMetrics.height * CGFloat(grid.rows) + 0.5)
        let hosting = NSHostingView(rootView: panel.makeView().frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.orderBack(nil)
        defer { window.close() }
        panel.resize(to: grid)
        panel.activate(context: ToolContext())
        try await settle(0.15)
        let terminal = try #require(findHost(in: hosting)).terminal
        panel.run("stty -echo; if [ -n \"$ZSH_VERSION\" ]; then unsetopt zle; fi; PS1=''; PS2=''; RPROMPT=''; printf '\\033[2J\\033[HAGENT-READY\\n'")
        try await waitFor(terminal, containing: "AGENT-READY")
        let questionArgument = styled ? "--prompt-file " + shellQuote(promptFile.path) : shellQuote(prompt)
        let command = "printf '\\033[2J\\033[H'; HOME=" + shellQuote(directory.path)
            + " FLEET_AGENT_LLM_URL=" + shellQuote(endpoint)
            + " FLEET_AGENT_LEDGER=" + shellQuote(directory.appendingPathComponent("meter.txt").path)
            + " " + shellQuote(binary) + " propose " + questionArgument
            + "; fleet_output_status=$?; printf '\\nPROPOSAL-EXIT:%s\\n' \"$fleet_output_status\""
        panel.run(command)
        if styled {
            try await waitFor(terminal, containing: "Preparing proposal", timeout: 3)
            #expect(!bufferText(terminal).contains("PROPOSAL-EXIT:"),
                    "The live preparing status must arrive before the HTTP fixture completes.")
            _ = try capture(terminal, name: "agent-proposal-preparing-dark")
        }
        try await waitFor(terminal, containing: "PROPOSAL-EXIT:", timeout: 8)
        let output = selectedText(terminal)
        terminal.selectNone()
        _ = try capture(terminal, name: "agent-proposal-dark")
        window.appearance = NSAppearance(named: .aqua)
        try await settle(0.15)
        _ = try capture(terminal, name: "agent-proposal-light")
        if let directory = evidenceDirectory {
            let receipt: [String: Any] = [
                "entryPoint": "TerminalPanel.run -> actual fleet-agent CLI -> deterministic loopback HTTP fixture -> SwiftTerm",
                "modelInference": false,
                "agentBinary": binary,
                "endpoint": endpoint,
                "promptTransport": styled ? "--prompt-file" : "inline argv",
                "selectedOutput": output,
                "expectedReply": expectedReply,
                "successExitObserved": output.contains("PROPOSAL-EXIT:0"),
                "bodyPreserved": output.contains(expectedReply),
                "preparingLabelObserved": output.contains("Preparing proposal"),
                "proposalLabelObserved": output.contains("\nProposal\n")
            ]
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("agent-proposal-receipt.json"))
        }
        #expect(output.contains("PROPOSAL-EXIT:0"), "The real CLI must complete the HTTP fixture successfully: \(output)")
        #expect(output.contains(expectedReply), "The model reply bytes must survive rendering and selection.")
        if styled {
            let snapshot = try #require(terminal.terminalContentSnapshot(region: .viewport))
            let row = try #require(snapshot.rows.first { $0.text == "Proposal" })
            #expect(row.cells[0].attribute.style.contains(.bold) == true)
        }
    }

    @MainActor
    @Test("The terminal preserves short, wrapped, error and streamed shell output")
    func actualShellOutput() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.finishLaunching()

        let socket = "fleet-output-test-" + UUID().uuidString
        let panel = TerminalPanel(shellSocket: socket)
        let grid = TerminalGrid(columns: 56, rows: 22)
        let size = CGSize(width: panel.cellMetrics.width * CGFloat(grid.columns) + panel.reservedWidth + 0.5,
                          height: panel.cellMetrics.height * CGFloat(grid.rows) + 0.5)
        let hosting = NSHostingView(rootView: panel.makeView().frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.orderBack(nil)
        defer { window.close(); killServer(socket) }
        panel.resize(to: grid)
        panel.activate(context: ToolContext())
        try await settle(0.15)
        let host = try #require(findHost(in: hosting))
        let terminal = host.terminal
        try await waitGrid(terminal, columns: grid.columns, rows: grid.rows)
        #expect(terminal.process.running)
        #expect(!terminal.isUsingMetalRenderer)

        panel.run("stty -echo; if [ -n \"$ZSH_VERSION\" ]; then unsetopt zle; fi; PS1=''; PS2=''; RPROMPT=''; printf '\\033[2J\\033[HREADY-fleet-output\\n'")
        try await waitFor(terminal, containing: "READY-fleet-output")
        panel.run("printf '\\033[2J\\033[H'")
        try await settle(0.2)
        let blank = try bitmap(hosting)

        panel.run("printf 'COMMAND  fleetctl status\\nRESULT   3 services healthy\\nSTATUS   ready\\n'")
        try await waitFor(terminal, containing: "STATUS   ready")
        let short = selectedText(terminal)
        #expect(withoutCellPadding(short).contains("COMMAND  fleetctl status\nRESULT   3 services healthy\nSTATUS   ready"))
        terminal.selectNone()
        var shortBitmap = try capture(hosting, name: "regression-short-dark")
        let renderedDeadline = Date().addingTimeInterval(2)
        while changedPixels(blank, shortBitmap) <= 500, Date() < renderedDeadline {
            try await settle(0.05)
            shortBitmap = try capture(terminal, name: "regression-short-dark")
        }
        #expect(changedPixels(blank, shortBitmap) > 500,
                "The AppKit capture must contain actual rendered output glyphs.")

        let long = "WRAP-BEGIN:" + String(repeating: "abcdefghij-", count: 20) + ":WRAP-END"
        panel.run("printf '%s\\n' " + shellQuote(long))
        try await waitFor(terminal, containing: "WRAP-END")
        #expect(selectedText(terminal).contains(long), "Soft wraps must preserve the original copy text.")
        terminal.selectNone()
        let wrapLines = bufferLines(terminal)
        let start = try #require(wrapLines.firstIndex(where: { $0.hasPrefix("WRAP-BEGIN:") }))
        #expect(wrapLines[start].count == grid.columns)
        #expect(wrapLines[start + 1].hasPrefix(String(long.dropFirst(grid.columns).prefix(9))))
        _ = try capture(terminal, name: "regression-wrapped-dark")

        panel.run("printf '\\033[31mERROR: permission denied at /tmp/fleet-output-test\\033[0m\\n' >&2; false")
        try await waitFor(terminal, containing: "ERROR: permission denied")
        #expect(selectedText(terminal).contains("ERROR: permission denied at /tmp/fleet-output-test"))
        terminal.selectNone()
        let errorSnapshot = try #require(terminal.terminalContentSnapshot(region: .viewport))
        let errorRow = try #require(errorSnapshot.rows.first { $0.text.hasPrefix("ERROR:") })
        #expect(errorRow.cells[0].attribute.fg == .ansi256(code: 1))
        _ = try capture(terminal, name: "regression-error-dark")

        panel.run("printf 'STREAM-BEGIN: first'; /bin/sleep 1.5; printf ' + second\\nSTREAM-END\\n'")
        try await waitFor(terminal, containing: "STREAM-BEGIN: first", timeout: 0.35)
        #expect(!bufferText(terminal).contains("STREAM-END"))
        _ = try capture(terminal, name: "regression-streaming-partial-dark")
        try await waitFor(terminal, containing: "STREAM-END")
        #expect(withoutCellPadding(selectedText(terminal)).contains("STREAM-BEGIN: first + second\nSTREAM-END"))
        terminal.selectNone()
        _ = try capture(terminal, name: "regression-streaming-complete-dark")

        panel.run("printf 'UNICODE: café 漢字 👩🏽‍💻\\nCONTROL: obsolete'; printf '\\r\\033[2KCONTROL: final\\n'")
        try await waitFor(terminal, containing: "CONTROL: final")
        let controls = selectedText(terminal)
        #expect(controls.contains("UNICODE: café 漢字 👩🏽‍💻"))
        #expect(controls.contains("CONTROL: final"))
        #expect(!controls.contains("CONTROL: obsolete"))
        #expect(!controls.contains("\u{1b}"), "Copied text must not contain terminal control bytes.")
        terminal.selectNone()
        _ = try capture(terminal, name: "regression-unicode-control-dark")

        panel.run("i=1; while [ $i -le 36 ]; do printf 'SCROLL %02d: preserved output\\n' \"$i\"; i=$((i + 1)); done; printf 'SCROLL-READY\\n'; /bin/sleep 1.25; printf 'STREAM-WHILE-SCROLLED\\n'")
        try await waitFor(terminal, containing: "SCROLL-READY")
        _ = try capture(terminal, name: "regression-scrollback-dark")
        try await waitFor(terminal, containing: "STREAM-WHILE-SCROLLED")
        let history = try paneHistory(socket: socket)
        for index in 1...36 {
            #expect(history.contains(String(format: "SCROLL %02d: preserved output", index)))
        }
        #expect(history.contains("SCROLL-READY"))
        #expect(history.contains("STREAM-WHILE-SCROLLED"))
        terminal.selectNone()

        panel.run("printf '\\033[?1hMODE-READY\\n'")
        try await waitFor(terminal, containing: "MODE-READY")
        var state = try #require(terminal.terminalContentSnapshot(region: .viewport)).inputState
        #expect(state.applicationCursor)
        panel.resize(to: TerminalGrid(columns: 40, rows: 18))
        try await waitGrid(terminal, columns: 40, rows: 18)
        state = try #require(terminal.terminalContentSnapshot(region: .viewport)).inputState
        #expect(state.applicationCursor)
        #expect(history.contains(String(long.prefix(9))) && history.contains(String(long.suffix(9))),
                "Reflow must preserve original long output.")
        terminal.selectNone()
        _ = try capture(terminal, name: "regression-narrow-reflow-dark")
        panel.run("printf '\\033[?1l\\033[2J\\033[HCOMMAND  fleetctl status\\nRESULT   3 services healthy\\nSTATUS   ready-light\\n'")
        try await waitFor(terminal, containing: "STATUS   ready-light")
        try await settle(0.15)
        window.appearance = NSAppearance(named: .aqua)
        try await settle(0.15)
        _ = try capture(terminal, name: "regression-short-light")

        var agentErrorOutput: String?
        if let binary = ProcessInfo.processInfo.environment["FLEET_TERMINAL_AGENT_BINARY"] {
            try #require(FileManager.default.isExecutableFile(atPath: binary))
            panel.resize(to: grid)
            try await waitGrid(terminal, columns: grid.columns, rows: grid.rows)
            try await settle(0.1)
            window.appearance = NSAppearance(named: .darkAqua)
            panel.run("printf '\\033[2J\\033[H'; FLEET_AGENT_LLM_URL='' " + shellQuote(binary)
                + " propose 'inspect memory'; fleet_output_status=$?; printf '\\nAGENT-EXIT:%s\\n' \"$fleet_output_status\"")
            try await waitFor(terminal, containing: "AGENT-EXIT:1")
            let error = "fleet-agent: inference is not configured: set FLEET_AGENT_LLM_URL to an already running loopback model endpoint"
            let errorRows = [
                "fleet-agent: inference is not configured: set FLEET_AGEN",
                "T_LLM_URL to an already running loopback model endpoint"
            ]
            #expect(errorRows.joined() == error)
            #expect(terminal.terminalDimensions.cols == grid.columns)
            agentErrorOutput = selectedText(terminal)
            #expect(agentErrorOutput?.contains(errorRows.joined(separator: "\n") + "\n\n") == true,
                    "The actual CLI diagnostic must preserve the baseline's exact physical copy break.")
            terminal.selectNone()
            let snapshot = try #require(terminal.terminalContentSnapshot(region: .viewport))
            let diagnosticIndex = try #require(snapshot.rows.firstIndex { $0.text.hasPrefix("fleet-agent:") })
            #expect(snapshot.rows[diagnosticIndex].text == errorRows[0])
            #expect(snapshot.rows[diagnosticIndex + 1].text == errorRows[1])
            if ProcessInfo.processInfo.environment["FLEET_TERMINAL_EXPECT_AGENT_STYLE"] == "1" {
                let headingRow = try #require(snapshot.rows.first { $0.text == "Error" })
                #expect(headingRow.cells[0].attribute.style.contains(.bold) == true)
            }
            _ = try capture(terminal, name: "agent-error-dark")
            window.appearance = NSAppearance(named: .aqua)
            try await settle(0.15)
            _ = try capture(terminal, name: "agent-error-light")
        }

        if let directory = evidenceDirectory {
            var receipt: [String: Any] = [
                "entryPoint": "TerminalPanel.activate/resize/run -> login shell PTY -> LocalProcessTerminalView",
                "renderer": "SwiftTerm AppKit CoreGraphics (Metal disabled)",
                "desktopInteraction": false,
                "clipboardMutation": false,
                "selectionPath": "TerminalView.selectAll/getSelection; same text extraction as Copy",
                "samplePurpose": "shell regression samples; not Fleet Agent product output",
                "scenarios": ["short", "56-column wrap", "stderr ANSI red", "partial and completed streaming",
                              "Unicode graphemes", "CR plus erase-line", "scrollback while streaming",
                              "40-column reflow preserves application cursor mode", "light and dark capture"],
                "capturedGlyphPixelsChanged": changedPixels(blank, shortBitmap),
                "selectedOutput": try paneHistory(socket: socket)
            ]
            if let agentErrorOutput {
                receipt["agentBinary"] = ProcessInfo.processInfo.environment["FLEET_TERMINAL_AGENT_BINARY"]
                receipt["agentErrorSelection"] = agentErrorOutput
            }
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("terminal-rendering-receipt.json"))
        }
    }

    @MainActor private func waitGrid(_ terminal: LocalProcessTerminalView, columns: Int, rows: Int) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !(terminal.terminalDimensions.cols == columns && terminal.terminalDimensions.rows == rows), Date() < deadline {
            try await settle(0.03)
        }
        let dimensions = terminal.terminalDimensions
        if dimensions.cols != columns || dimensions.rows != rows {
            print("GRID-DIAG frame=\(terminal.frame) dims=\(dimensions) want=\(columns)x\(rows) style=\(terminal.scrollerStyle.rawValue) scrollerW=\(NSScroller.scrollerWidth(for: .regular, scrollerStyle: terminal.scrollerStyle))")
        }
        #expect(dimensions.cols == columns)
        #expect(dimensions.rows == rows)
    }

    @MainActor private func findHost(in view: NSView) -> PTYHostView? {
        (view as? PTYHostView) ?? view.subviews.lazy.compactMap { findHost(in: $0) }.first
    }

    @MainActor private func bufferLines(_ view: TerminalView) -> [String] {
        guard let snapshot = view.terminalContentSnapshot(region: .all) else { return [] }
        return snapshot.rows.map { $0.text }
    }

    @MainActor private func bufferText(_ view: TerminalView) -> String {
        bufferLines(view).joined(separator: "\n")
    }

    @MainActor private func selectedText(_ view: TerminalView) -> String {
        view.selectAll()
        return view.getSelection() ?? ""
    }

    private func withoutCellPadding(_ text: String) -> String {
        text.replacingOccurrences(of: " +(?=\\n|$)", with: "", options: .regularExpression)
    }

    private func paneHistory(socket: String) throws -> String {
        let tmux = try #require(ToolBinary.resolve("tmux"))
        let process = Process()
        process.executableURL = tmux
        process.arguments = ["-L", socket, "capture-pane", "-p", "-t", "shell", "-S", "-3000"]
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func killServer(_ socket: String) {
        guard let tmux = ToolBinary.resolve("tmux") else { return }
        let process = Process()
        process.executableURL = tmux
        process.arguments = ["-L", socket, "kill-server"]
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil { process.waitUntilExit() }
    }

    @MainActor private func waitFor(_ view: TerminalView, containing marker: String,
                                    timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !bufferText(view).contains(marker), Date() < deadline { try await settle(0.01) }
        try #require(bufferText(view).contains(marker), "Missing live PTY output: \(marker)")
        try await settle(0.04)
    }

    @MainActor private func settle(_ duration: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(duration))
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private var evidenceDirectory: URL? {
        ProcessInfo.processInfo.environment["FLEET_TERMINAL_EVIDENCE_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    @MainActor private func bitmap(_ view: NSView) throws -> NSBitmapImageRep {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        if let context = NSGraphicsContext(bitmapImageRep: rep), let layer = view.layer {
            layer.render(in: context.cgContext)
        } else {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        let png = try #require(rep.representation(using: .png, properties: [:]))
        return try #require(NSBitmapImageRep(data: png))
    }

    @MainActor private func capture(_ view: NSView, name: String) throws -> NSBitmapImageRep {
        let rep = try bitmap(view)
        if let directory = evidenceDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent(name + ".png"))
        }
        return rep
    }

    private func changedPixels(_ before: NSBitmapImageRep, _ after: NSBitmapImageRep) -> Int {
        guard before.pixelsWide == after.pixelsWide, before.pixelsHigh == after.pixelsHigh else { return 0 }
        var changed = 0
        for y in 0..<before.pixelsHigh {
            for x in 0..<before.pixelsWide {
                if before.colorAt(x: x, y: y) != after.colorAt(x: x, y: y) { changed += 1 }
            }
        }
        return changed
    }
}
