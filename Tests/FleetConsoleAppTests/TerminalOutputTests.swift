import AppKit
import SwiftUI
import SwiftTerm
import Testing
@testable import FleetConsoleApp

/// Exercises the shipping TerminalPanel -> shell PTY -> SwiftTerm view path.
/// No desktop input, daemon mutation, clipboard mutation, or synthetic feed is involved.
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
            // cat streams the bytes produced by the Rust production formatter.
            // This verifies rendering, not model admission or inference success.
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
            let emulator = terminal.getTerminal()
            let heading = name == "error" ? "Error" : "Proposal"
            let row = try #require((0..<emulator.rows).first(where: { row in
                emulator.getLine(row: row)?.translateToString(trimRight: true) == heading
            }))
            #expect(emulator.getCharData(col: 0, row: row)?.attribute.style.contains(.bold) == true)
            #expect(!output.contains("\u{1b}"), "Selection exposes readable text, not ANSI bytes.")
            switch name {
            case "short":
                #expect(output.contains("TEST DATA: A short read-only proposal for formatter/PTY verification."))
                #expect(output.contains("Preparing proposal"))
            case "wrapped":
                let paragraph = String(repeating: "Evidence, command, result and status remain readable with every original word preserved. ", count: 5)
                // SwiftTerm's existing selection trims line-ending padding.
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
        // Keep the actual CLI's inference lock and controller discovery out of
        // the operator's home. Only the owned loopback response is exercised.
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
            let emulator = terminal.getTerminal()
            let row = try #require((0..<emulator.rows).first(where: { row in
                emulator.getLine(row: row)?.translateToString(trimRight: true) == "Proposal"
            }))
            #expect(emulator.getCharData(col: 0, row: row)?.attribute.style.contains(.bold) == true)
        }
    }

    @MainActor
    @Test("The terminal preserves short, wrapped, error and streamed shell output")
    func actualShellOutput() async throws {
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
        defer { window.close() } // Closes and reaps only this test's owned shell.
        panel.resize(to: grid)
        panel.activate(context: ToolContext())
        try await settle(0.15)
        let host = try #require(findHost(in: hosting))
        let terminal = host.terminal
        let emulator = terminal.getTerminal()
        #expect(emulator.cols == grid.columns)
        #expect(emulator.rows == grid.rows)
        #expect(terminal.process.running)
        #expect(!terminal.isUsingMetalRenderer)

        // Standardize only this owned shell. Its login startup still ran through
        // TerminalPanel.activate; no profile or user preference is changed.
        panel.run("stty -echo; if [ -n \"$ZSH_VERSION\" ]; then unsetopt zle; fi; PS1=''; PS2=''; RPROMPT=''; printf '\\033[2J\\033[HREADY-fleet-output\\n'")
        try await waitFor(terminal, containing: "READY-fleet-output")
        panel.run("printf '\\033[2J\\033[H'")
        try await settle(0.2)
        let blank = try bitmap(terminal)

        panel.run("printf 'COMMAND  fleetctl status\\nRESULT   3 services healthy\\nSTATUS   ready\\n'")
        try await waitFor(terminal, containing: "STATUS   ready")
        let short = selectedText(terminal)
        // Cleared cells may copy as trailing padding depending on the SDK.
        // Preserve hard line breaks and all spacing inside the actual output.
        #expect(withoutCellPadding(short).contains("COMMAND  fleetctl status\nRESULT   3 services healthy\nSTATUS   ready"))
        terminal.selectNone()
        let shortBitmap = try capture(terminal, name: "regression-short-dark")
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
        let errorRow = try #require((0..<emulator.rows).first(where: { row in
            emulator.getLine(row: row)?.translateToString(trimRight: true).hasPrefix("ERROR:") == true
        }))
        #expect(emulator.getCharData(col: 0, row: errorRow)?.attribute.fg == .ansi256(code: 1))
        _ = try capture(terminal, name: "regression-error-dark")

        // A sleeping live shell creates a real chunk boundary in the PTY reader.
        panel.run("printf 'STREAM-BEGIN: first'; /bin/sleep 0.45; printf ' + second\\nSTREAM-END\\n'")
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
        #expect(terminal.canScroll)
        #expect(emulator.buffer.yDisp > 0)
        terminal.scrollUp(lines: 8)
        let scrolledRow = emulator.buffer.yDisp
        #expect(terminal.scrollPosition < 1)
        _ = try capture(terminal, name: "regression-scrollback-dark")
        try await waitFor(terminal, containing: "STREAM-WHILE-SCROLLED")
        #expect(emulator.buffer.yDisp == scrolledRow,
                "Streaming must preserve a user-scrolled viewport.")
        terminal.scroll(toPosition: 1)
        #expect(terminal.scrollPosition == 1)
        let allOutput = selectedText(terminal)
        #expect(allOutput.contains("SCROLL 01: preserved output"))
        #expect(allOutput.contains("STREAM-WHILE-SCROLLED"))
        terminal.selectNone()

        // Narrow resize goes through the production coalesced-grid endpoint,
        // which deliberately avoids a DECSTR reset of the running emulator.
        panel.run("printf '\\033[?1hMODE-READY\\n'")
        try await waitFor(terminal, containing: "MODE-READY")
        #expect(emulator.applicationCursor)
        panel.resize(to: TerminalGrid(columns: 40, rows: 18))
        #expect(emulator.cols == 40)
        #expect(emulator.rows == 18)
        #expect(emulator.applicationCursor)
        #expect(selectedText(terminal).contains(long), "Reflow must preserve original long output.")
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
            // Isolate CLI presentation from the separate narrow-resize case;
            // preserve its raw selection in the receipt for before/after review.
            panel.resize(to: grid)
            #expect(emulator.cols == grid.columns)
            #expect(emulator.rows == grid.rows)
            try await settle(0.1)
            window.appearance = NSAppearance(named: .darkAqua)
            panel.run("printf '\\033[2J\\033[H'; FLEET_AGENT_LLM_URL='' " + shellQuote(binary)
                + " propose 'inspect memory'; fleet_output_status=$?; printf '\\nAGENT-EXIT:%s\\n' \"$fleet_output_status\"")
            try await waitFor(terminal, containing: "AGENT-EXIT:1")
            let error = "fleet-agent: inference is not configured: set FLEET_AGENT_LLM_URL to an already running loopback model endpoint"
            // The installed baseline copies this diagnostic with one physical
            // wrap break at the original 56-column grid. Preserve that exact
            // copy behavior while checking every original diagnostic character.
            let errorRows = [
                "fleet-agent: inference is not configured: set FLEET_AGEN",
                "T_LLM_URL to an already running loopback model endpoint"
            ]
            #expect(errorRows.joined() == error)
            #expect(emulator.cols == grid.columns)
            agentErrorOutput = selectedText(terminal)
            #expect(agentErrorOutput?.contains(errorRows.joined(separator: "\n") + "\n\n") == true,
                    "The actual CLI diagnostic must preserve the baseline's exact physical copy break.")
            terminal.selectNone()
            let diagnosticRow = try #require((0..<emulator.rows).first(where: { row in
                emulator.getLine(row: row)?.translateToString(trimRight: true).hasPrefix("fleet-agent:") == true
            }))
            #expect(emulator.getLine(row: diagnosticRow)?.translateToString(trimRight: true) == errorRows[0])
            #expect(emulator.getLine(row: diagnosticRow + 1)?.translateToString(trimRight: true) == errorRows[1])
            if ProcessInfo.processInfo.environment["FLEET_TERMINAL_EXPECT_AGENT_STYLE"] == "1" {
                let headingRow = try #require((0..<emulator.rows).first(where: { row in
                    emulator.getLine(row: row)?.translateToString(trimRight: true) == "Error"
                }))
                #expect(emulator.getCharData(col: 0, row: headingRow)?.attribute.style.contains(.bold) == true)
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
                "selectedOutput": allOutput
            ]
            if let agentErrorOutput {
                receipt["agentBinary"] = ProcessInfo.processInfo.environment["FLEET_TERMINAL_AGENT_BINARY"]
                receipt["agentErrorSelection"] = agentErrorOutput
            }
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("terminal-rendering-receipt.json"))
        }
    }

    @MainActor private func findHost(in view: NSView) -> PTYHostView? {
        (view as? PTYHostView) ?? view.subviews.lazy.compactMap { findHost(in: $0) }.first
    }

    @MainActor private func bufferLines(_ view: TerminalView) -> [String] {
        let terminal = view.getTerminal()
        var row = terminal.buffer.totalLinesTrimmed
        var lines: [String] = []
        while let line = terminal.getScrollInvariantLine(row: row) {
            lines.append(line.translateToString(trimRight: true, skipNullCellsFollowingWide: true,
                                                characterProvider: { terminal.getCharacter(for: $0) })
                .replacingOccurrences(of: "\u{0}", with: " "))
            row += 1
        }
        return lines
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

    @MainActor private func waitFor(_ view: TerminalView, containing marker: String,
                                    timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !bufferText(view).contains(marker), Date() < deadline { try await settle(0.01) }
        try #require(bufferText(view).contains(marker), "Missing live PTY output: \(marker)")
        try await settle(0.04) // Let the main-queue PTY delivery and display timer execute.
    }

    @MainActor private func settle(_ duration: TimeInterval) async throws {
        // LocalProcess delivers stdout on DispatchQueue.main. A nested run loop
        // inside a synchronous main-actor test cannot drain that GCD delivery;
        // suspending the test lets the real PTY bridge feed the terminal view.
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
        view.setNeedsDisplay(view.bounds)
        view.window?.displayIfNeeded()
        view.cacheDisplay(in: view.bounds, to: rep)
        // cacheDisplay may reuse a backing representation; an independent
        // snapshot makes blank/output pixel comparison meaningful.
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
