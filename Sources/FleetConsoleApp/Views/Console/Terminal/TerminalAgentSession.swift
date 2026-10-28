import Foundation
import Observation
import FleetCore

/// Explicit app handoff, not a guess based on a process title or terminal output.
/// Only these launches get agent controls; an arbitrary command in Shell remains a shell command.
struct TerminalAgentRequest: Sendable {
    let kind: FixAgentKind
    let executable: URL
    let prompt: String
    let reportURL: URL
    let workingDirectory: URL
    let subject: String
    let suggestions: [TroubleshootingSuggestion]

    @MainActor var launch: PTYSession.Launch {
        let arguments: [String]
        switch kind {
        case .claude, .codex: arguments = [prompt]
        case .fleetAgent: arguments = ["propose", "--prompt-file", reportURL.path]
        }
        return PTYSession.Launch(executable: executable, arguments: arguments,
                                 workingDirectory: ToolBinary.usableDirectory(workingDirectory),
                                 environment: ToolBinary.environment(withSearchPath: true))
    }
}

@Observable
@MainActor
final class TerminalAgentSession: Identifiable {
    let id = UUID()
    let request: TerminalAgentRequest
    let createdAt = Date()
    let pty: PTYSession
    private(set) var stopRequested = false

    init(request: TerminalAgentRequest) {
        self.request = request
        pty = PTYSession(refusesBelowMinimum: request.kind != .fleetAgent)
    }

    func stop() {
        stopRequested = true
        pty.terminate()
    }

    var status: String {
        switch pty.phase {
        case .idle: return "Waiting for terminal layout"
        case .running: return "Running · activity unverified"
        case .stopping: return "Stopping app-owned process group"
        case .exited(let status):
            guard let status else {
                if stopRequested { return pty.launch == nil ? "Cancelled before launch" : "Stopped by operator · review work" }
                return "Ended · outcome unverified"
            }
            let signal = status & 0x7f
            if signal != 0 { return "Ended · signal \(signal)" }
            let code = (status >> 8) & 0xff
            return "Exited \(code) · review output"
        }
    }

    var policy: String {
        request.kind == .fleetAgent
            ? "Read-only proposal · no service changes"
            : "Interactive external agent · its own permissions and provider billing apply"
    }
}
