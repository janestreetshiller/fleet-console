import Foundation
import Observation
import FleetCore

// The designated fixer: one agent outside the app that FleetConsole hands its
// problems to.
//
// The app observes and the controller supervises; neither edits your code or
// your configuration. When something needs a fix, the app extracts what it knows
// — the problem, the service's record, its recent events, where its logs are —
// into a report file, and starts the agent you designated on that report in the
// dashboard's own terminal, in the service's working directory. You watch it,
// answer it, stop it. It acts on managed services through `fleetctl`, the same
// verbs every agent uses, and reports back through `fleetctl notify`, so its
// progress lands in the Agents tab beside everyone else's.

/// The agents FleetConsole knows how to start on a report.
enum FixAgentKind: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case fleetAgent = "fleet-agent"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .fleetAgent: return "Fleet Agent"
        }
    }

    /// The executable resolved on the search path, and the ID the agent posts
    /// its mailbox messages under.
    var executable: String { rawValue }

    /// The command line typed into the terminal. Each starts an interactive
    /// session with the prompt as its first turn, except the resident agent,
    /// whose `ask` runs one bounded tool loop.
    func commandLine(prompt: String) -> String {
        switch self {
        case .claude, .codex: return "\(executable) \(prompt.shellQuoted)"
        case .fleetAgent: return "\(executable) ask \(prompt.shellQuoted)"
        }
    }
}

/// Which fixer is designated, and which are installed. One per Mac.
@Observable
@MainActor
final class FixAgentSettings {
    static let shared = FixAgentSettings()

    private static let key = "fleetconsole.fixAgent"
    private let defaults: UserDefaults
    private let resolve: (String) -> URL?

    /// The installed fixers, in `FixAgentKind` order.
    private(set) var installed: [FixAgentKind] = []

    var designated: FixAgentKind? {
        didSet { defaults.set(designated?.rawValue, forKey: Self.key) }
    }

    init(defaults: UserDefaults = .standard, resolve: @escaping (String) -> URL? = ToolBinary.resolve) {
        self.defaults = defaults
        self.resolve = resolve
        designated = defaults.string(forKey: Self.key).flatMap(FixAgentKind.init(rawValue:))
        reload()
    }

    /// Re-reads the search path. A designation whose agent has gone falls back
    /// to the first installed one rather than pointing at nothing.
    func reload() {
        installed = FixAgentKind.allCases.filter { resolve($0.executable) != nil }
        if designated.map({ !installed.contains($0) }) ?? true {
            designated = installed.first
        }
    }
}

/// What the fixer is handed: the problems, and everything the app knows about
/// the services they concern, as one Markdown file.
enum FixReport {
    static func markdown(items: [AttentionItem], services: [ServiceRecord], events: [ServiceEvent],
                         host: String, generatedAt: Date = Date()) -> String {
        var lines = ["# FleetConsole fix request", "",
                     "Generated \(ISO8601DateFormatter().string(from: generatedAt)) on \(host).", ""]
        lines.append("## Problems")
        lines.append("")
        for item in items {
            lines.append("- **\(item.severity == .critical ? "Critical" : "Warning"): \(item.title)** — \(item.detail)"
                         + " (since \(ISO8601DateFormatter().string(from: item.since)))")
        }
        for service in services {
            lines += ["", "## Service `\(service.friendlyName)` (\(service.id))", "",
                      "- State: \(service.state.rawValue)",
                      "- Owner agent: \(service.ownerAgent) — purpose: \(service.purpose)",
                      "- Command: `\(service.command.joined(separator: " "))`",
                      "- Working directory: `\(service.cwd)`",
                      "- PID \(service.pid.map(String.init) ?? "none"), process group \(service.pgid.map(String.init) ?? "none")",
                      "- Ports declared: \(service.declaredPorts.map(String.init).joined(separator: ", ").ifEmpty("none"));"
                        + " listening: \(service.evidence.listeningPorts.map(String.init).joined(separator: ", ").ifEmpty("none"))",
                      "- Health: \(service.evidence.healthDetail ?? "no check recorded");"
                        + " consecutive failures \(service.consecutiveHealthFailures)",
                      "- Restarts: \(service.restartCount); last exit code: \(service.lastExitCode.map(String.init) ?? "none")",
                      "- Lease expires: \(ISO8601DateFormatter().string(from: service.leaseExpiresAt))",
                      "- Logs: stdout `\(service.stdoutPath)`, stderr `\(service.stderrPath)`"]
            let recent = events.filter { $0.serviceID == service.id }.prefix(12)
            if !recent.isEmpty {
                lines += ["", "Recent events, newest first:", ""]
                lines += recent.map { "- \(ISO8601DateFormatter().string(from: $0.ts)) · \($0.kind.rawValue) · \($0.detail)" }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the report where the fixer can read it and returns its location.
    static func write(_ markdown: String, now: Date = Date()) throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FleetConsole/fix-reports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("fix-\(stamp).md")
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// The first turn: read the report, fix through the controller, report back.
    static func prompt(reportPath: String, agentID: String, fleetctl: String) -> String {
        "FleetConsole found problems on this Mac and wrote them up at \(reportPath). "
            + "Read it, find the cause of each problem, and fix what you can. "
            + "Act on managed services only through \(fleetctl) (show, logs, restart, stop, renew); "
            + "never signal a process FleetConsole manages directly. "
            + "Post progress and anything you need from me with: "
            + "\(fleetctl) notify --agent \(agentID) --message \"…\" (add --ask for a question)."
    }
}

extension AppModel {
    /// Hands `items` to the designated fixer: writes the report, then opens the
    /// dashboard's terminal in the service's directory and starts the agent.
    /// Returns a sentence to show when it could not.
    @discardableResult
    func sendToFixer(_ items: [AttentionItem], openDashboard: () -> Void,
                     settings: FixAgentSettings = .shared) -> String? {
        guard !items.isEmpty else { return "Nothing needs fixing." }
        settings.reload()
        guard let fixer = settings.designated else {
            return "Install Claude Code, Codex or the Fleet agent to hand problems to it."
        }
        let services = items.compactMap { $0.serviceID }.compactMap { service(id: $0) }
        loadEvents(serviceID: nil, limit: 200) { [weak self] events in
            guard let self else { return }
            let markdown = FixReport.markdown(items: items, services: services, events: events,
                                              host: Host.current().localizedName ?? "this Mac")
            guard let report = try? FixReport.write(markdown) else {
                self.actionError = "The fix report could not be written."
                return
            }
            let fleetctl = ToolBinary.resolve("fleetctl")?.path
                ?? Bundle.main.resourceURL?.appendingPathComponent("bin/fleetctl").path ?? "fleetctl"
            let prompt = FixReport.prompt(reportPath: report.path, agentID: fixer.executable,
                                          fleetctl: fleetctl.shellQuoted)
            let directory = services.count == 1 && !services[0].cwd.isEmpty ? services[0].cwd : NSHomeDirectory()
            NotificationCenter.default.post(name: ConsoleCommand.runInTerminal, object: nil, userInfo: [
                ConsoleCommand.userInfoCommand: fixer.commandLine(prompt: prompt),
                ConsoleCommand.userInfoDirectory: directory,
                ConsoleCommand.userInfoSubject: "\(fixer.title) · \(items.count == 1 ? items[0].title : "\(items.count) problems")",
            ])
        }
        openDashboard()
        return nil
    }
}

extension String {
    /// POSIX single-quoting: safe to type into any login shell.
    var shellQuoted: String { "'" + replacingOccurrences(of: "'", with: "'\\''") + "'" }

    fileprivate func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
