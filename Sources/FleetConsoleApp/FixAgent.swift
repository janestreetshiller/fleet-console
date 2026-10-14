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
// answer it, stop it. External fixers act through `fleetctl` and report through
// its mailbox. The bundled fleet-agent reads the complete saved request and returns
// a read-only proposal for the operator to review.

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

    /// The executable name and the agent's mailbox ID.
    var executable: String { rawValue }

    /// The command line typed into the terminal. The bundled agent produces a
    /// read-only proposal; external agents retain their interactive workflow.
    func commandLine(prompt: String, executableURL: URL? = nil, promptFileURL: URL? = nil) -> String {
        let binary = executableURL?.path.shellQuoted ?? executable
        switch self {
        case .claude, .codex: return "\(binary) \(prompt.shellQuoted)"
        case .fleetAgent:
            if let promptFileURL { return "\(binary) propose --prompt-file \(promptFileURL.path.shellQuoted)" }
            return "\(binary) propose \(prompt.shellQuoted)"
        }
    }
}

/// Bundled fleet-agent has the app's proposal policy. An older copy on
/// PATH must not replace it; external fixers keep their existing resolution.
enum FixAgentBinary {
    static func resolve(_ name: String) -> URL? {
        resolve(name, resourceURL: Bundle.main.resourceURL, searchPathResolve: ToolBinary.resolve)
    }

    static func resolve(_ name: String, resourceURL: URL?, searchPathResolve: (String) -> URL?) -> URL? {
        if name == FixAgentKind.fleetAgent.executable,
           let bundled = resourceURL?.appendingPathComponent("bin/fleet-agent"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        return searchPathResolve(name)
    }
}

/// Which fixer is designated, and which are installed. One per Mac.
@Observable
@MainActor
final class FixAgentSettings {
    static let shared = FixAgentSettings()

    private static let key = "fleetconsole.fixAgent"
    private static let none = "none"
    private let defaults: UserDefaults
    private let resolve: (String) -> URL?
    @ObservationIgnored private var isReloading = false
    @ObservationIgnored private var isInitializing = true

    /// The installed fixers, in `FixAgentKind` order.
    private(set) var installed: [FixAgentKind] = []

    var designated: FixAgentKind? {
        didSet {
            if !isInitializing {
                if isReloading, designated == nil { defaults.removeObject(forKey: Self.key) }
                else { defaults.set(designated?.rawValue ?? Self.none, forKey: Self.key) }
            }
        }
    }

    init(defaults: UserDefaults = .standard, resolve: @escaping (String) -> URL? = FixAgentBinary.resolve) {
        self.defaults = defaults
        self.resolve = resolve
        designated = defaults.string(forKey: Self.key).flatMap(FixAgentKind.init(rawValue:))
        isInitializing = false
        reload()
    }

    /// External fixers can be selected by availability. Fleet Agent always
    /// requires an explicit designation, and an explicit None stays disabled.
    func reload() {
        installed = FixAgentKind.allCases.filter { resolve($0.executable) != nil }
        if designated == nil, defaults.string(forKey: Self.key) == Self.none { return }
        isReloading = true
        defer { isReloading = false }
        if designated.map({ !installed.contains($0) }) ?? true {
            designated = installed.first { $0 != .fleetAgent }
        }
    }

    func executableURL(for kind: FixAgentKind) -> URL? { resolve(kind.executable) }
}

/// What the fixer is handed: the problems, and everything the app knows about
/// the services they concern, as one Markdown file.
enum FixReport {
    static let maximumPromptBytes = 32 * 1024

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
        let url = location(now: now)
        try write(markdown, to: url)
        return url
    }

    /// Choose the location before writing so the complete first turn can be
    /// validated before any report is saved or command is dispatched.
    static func location(now: Date = Date()) -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FleetConsole/fix-reports", isDirectory: true)
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        // The shell can read after a second handoff is queued. Each request
        // must retain its own contents even when both arrive in the same second.
        return directory.appendingPathComponent("fix-\(stamp)-\(UUID().uuidString).md")
    }

    static func write(_ markdown: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
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

    /// fleet-agent has read-only observation tools and cannot open a report
    /// file. Give it the findings directly and ask only for a proposal.
    static func proposalPrompt(markdown: String) -> String {
        "FleetConsole found the problems below on this Mac. "
            + "Investigate with read-only tools and propose fixes for the operator to review. "
            + "Do not launch, restart, stop, renew or otherwise change any service.\n\n"
            + markdown
    }
}

extension AppModel {
    /// Hands `items` to the designated fixer: writes the report, then opens the
    /// dashboard's terminal in the service's directory and starts the agent.
    /// Returns a sentence to show when it could not.
    @discardableResult
    func sendToFixer(_ items: [AttentionItem], openDashboard: () -> Void,
                     settings: FixAgentSettings = .shared,
                     loadReportEvents: ((@escaping ([ServiceEvent]) -> Void) -> Void)? = nil,
                     writeReport: @escaping (String, URL) throws -> Void = FixReport.write) -> String? {
        guard !items.isEmpty else { return "Nothing needs fixing." }
        settings.reload()
        guard let fixer = settings.designated else {
            return "Choose Claude Code, Codex or Fleet Agent in the Fixer menu to hand problems to it."
        }
        guard let executableURL = settings.executableURL(for: fixer) else {
            return "\(fixer.title) could not be found. Choose an installed fixer."
        }
        let services = items.compactMap { $0.serviceID }.compactMap { service(id: $0) }
        let receiveEvents: ([ServiceEvent]) -> Void = { [weak self] events in
            guard let self else { return }
            let markdown = FixReport.markdown(items: items, services: services, events: events,
                                              host: Host.current().localizedName ?? "this Mac")
            let report = FixReport.location()
            let fleetctl = ToolBinary.resolve("fleetctl")?.path
                ?? Bundle.main.resourceURL?.appendingPathComponent("bin/fleetctl").path ?? "fleetctl"
            let prompt = fixer == .fleetAgent
                ? FixReport.proposalPrompt(markdown: markdown)
                : FixReport.prompt(reportPath: report.path, agentID: fixer.executable, fleetctl: fleetctl.shellQuoted)
            // Reject the complete request before writing or dispatching;
            // external fixers retain their report-file workflow.
            guard fixer != .fleetAgent || prompt.utf8.count <= FixReport.maximumPromptBytes else {
                self.actionError = "The fix request exceeds 32 KiB. Send fewer problems at once; no findings were truncated."
                return
            }
            // Keep the exact proposal prompt in the saved report instead of
            // echoing all findings and instructions into the shell command.
            do { try writeReport(fixer == .fleetAgent ? prompt : markdown, report) } catch {
                self.actionError = "The fix report could not be written."
                return
            }
            let directory = services.count == 1 && !services[0].cwd.isEmpty ? services[0].cwd : NSHomeDirectory()
            NotificationCenter.default.post(name: ConsoleCommand.runInTerminal, object: nil, userInfo: [
                ConsoleCommand.userInfoCommand: fixer.commandLine(prompt: prompt, executableURL: executableURL,
                                                                  promptFileURL: fixer == .fleetAgent ? report : nil),
                ConsoleCommand.userInfoDirectory: directory,
                ConsoleCommand.userInfoSubject: "\(fixer.title) · \(items.count == 1 ? items[0].title : "\(items.count) problems")",
            ])
        }
        if let loadReportEvents { loadReportEvents(receiveEvents) }
        else { loadEvents(serviceID: nil, limit: 200, completion: receiveEvents) }
        openDashboard()
        return nil
    }
}

extension String {
    /// POSIX single-quoting: safe to type into any login shell.
    var shellQuoted: String { "'" + replacingOccurrences(of: "'", with: "'\\''") + "'" }

    fileprivate func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
