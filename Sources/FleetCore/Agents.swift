import Foundation

// Agents: their sessions, their mailbox, and the profiles the UI groups them by.
// Sessions are ordinary processes rather than managed services; the mailbox lets
// one ask a question without the operator watching a terminal.
// MARK: - Agent sessions
//
// The coding agents you actually run — Claude Code, Codex, Gemini CLI, opencode,
// aider — are ordinary processes, not services launched through the controller.
// They are the thing you most want to see ("who is working right now, in which
// project"), so they are detected directly rather than requiring registration.

/// Who wrote the line a preview is showing. A tool result and a sentence the
/// agent wrote are different kinds of evidence about what it is doing, and
/// flattening them into one grey line loses the distinction that matters.
public enum AgentTurn: String, Codable, Sendable {
    case assistant      // the agent said something
    case user           // you (or a tool result) said something to it
    case tool           // the agent invoked a tool

    public var label: String {
        switch self {
        case .assistant: return "said"
        case .user: return "asked"
        case .tool: return "ran"
        }
    }

    public var symbol: String {
        switch self {
        case .assistant: return "quote.bubble"
        case .user: return "arrow.turn.down.right"
        case .tool: return "hammer"
        }
    }
}

public struct AgentSession: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var tool: String
    public var symbol: String
    public var pid: Int32
    /// Working directory, i.e. the project it is operating on.
    public var project: String?
    public var startedAt: Date?
    public var cpuPct: Double
    public var memMB: Double
    public var commandLine: String

    // MARK: Live transcript
    //
    // A session row that says "claude · fleet-console · pid 14446" answers *that*
    // an agent is running, which you could already see in Activity Monitor. What
    // you actually want to know is what it is doing right now, and for the tools
    // that keep a transcript on disk that is readable without asking the agent.
    // Everything below is nil when there is no transcript to read — an absent
    // preview is the honest rendering of "this tool does not publish one".

    /// The session identifier the tool itself uses — the "uid" in the transcript
    /// filename. Shown so a row can be tied back to a resumable session.
    public var sessionUID: String?
    /// The tool's own name for the session, when it has one.
    public var sessionName: String?
    /// Absolute path of the transcript the preview was read from.
    public var transcriptPath: String?
    /// The most recent turn, trimmed to one line.
    public var preview: String?
    public var previewTurn: AgentTurn?
    public var previewAt: Date?

    public init(id: String, tool: String, symbol: String = "terminal", pid: Int32,
                project: String? = nil, startedAt: Date? = nil, cpuPct: Double = 0,
                memMB: Double = 0, commandLine: String = "") {
        self.id = id
        self.tool = tool
        self.symbol = symbol
        self.pid = pid
        self.project = project
        self.startedAt = startedAt
        self.cpuPct = cpuPct
        self.memMB = memMB
        self.commandLine = commandLine
    }

    public var projectName: String {
        guard let project else { return "—" }
        return (project as NSString).lastPathComponent
    }

    public var summary: String {
        var parts = [sessionName ?? projectName]
        if let startedAt { parts.append("up \(Fmt.duration(Date().timeIntervalSince(startedAt)))") }
        parts.append("pid \(pid)")
        return parts.joined(separator: " · ")
    }

    /// "said 12s ago" — the age of the transcript line, not of the process.
    public var previewAge: String? {
        guard let previewAt, let previewTurn else { return nil }
        return "\(previewTurn.label) \(Fmt.relative(previewAt))"
    }
}

// MARK: - Agent messages
//
// A local mailbox so an agent can say something and get an answer without the
// operator having to be watching a terminal. Messages are append-only; a reply is
// the one field that can be written afterwards, and it is written exactly once.

public enum MessageKind: String, Codable, Sendable, CaseIterable {
    case status         // "here is what I did"
    case question       // needs a human answer before the agent can continue
    case problem        // something went wrong and the agent stopped

    public var label: String {
        switch self {
        case .status: return "Status"
        case .question: return "Question"
        case .problem: return "Problem"
        }
    }

    public var symbol: String {
        switch self {
        case .status: return "text.bubble"
        case .question: return "questionmark.bubble"
        case .problem: return "exclamationmark.bubble"
        }
    }
}

public struct AgentMessage: Codable, Sendable, Identifiable, Hashable {
    public var id: Int64
    public var agent: String
    public var serviceID: String?
    public var serviceName: String?
    public var kind: MessageKind
    public var body: String
    public var createdAt: Date
    /// Set when the agent wants an answer; drives the unanswered badge.
    public var needsReply: Bool
    public var reply: String?
    public var repliedAt: Date?
    /// Whether the operator has seen it (notifications fire once).
    public var seenAt: Date?

    public init(id: Int64 = 0, agent: String, serviceID: String? = nil, serviceName: String? = nil,
                kind: MessageKind = .status, body: String, createdAt: Date = Date(),
                needsReply: Bool = false, reply: String? = nil, repliedAt: Date? = nil,
                seenAt: Date? = nil) {
        self.id = id
        self.agent = agent
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.kind = kind
        self.body = body
        self.createdAt = createdAt
        self.needsReply = needsReply
        self.reply = reply
        self.repliedAt = repliedAt
        self.seenAt = seenAt
    }

    public var isAwaitingReply: Bool { needsReply && reply == nil }
}

// MARK: - Agents
//
// Ownership is the point of the registry, so it deserves to be a view of its own:
// "what has this agent left running, and when does it all expire" is the question
// you actually ask when an agent has gone quiet.

/// Everything known about one agent: what it is doing now, what it has done, and
/// what it has said.
public struct AgentProfile: Codable, Sendable, Identifiable, Hashable {
    public var id: String

    // Now
    public var running = 0
    public var paused = 0
    public var needingAttention = 0
    public var ports: [Int] = []
    public var cpuPct: Double = 0
    public var memMB: Double = 0
    public var nextLeaseExpiry: Date?

    // History
    public var totalLaunched = 0
    public var totalStopped = 0
    public var totalCrashed = 0
    /// Services the controller had to reap because this agent stopped renewing.
    public var totalLeaked = 0
    public var totalRestarts = 0
    public var healthFailures = 0
    public var totalRuntime: TimeInterval = 0
    public var firstSeen: Date?
    public var lastActivityAt: Date?
    public var projects: [String] = []
    public var purposes: [String] = []
    public var recentServices: [ServiceRecord] = []

    // Mailbox
    public var messageCount = 0
    public var awaitingReply = 0
    public var lastMessage: AgentMessage?

    public init(id: String) { self.id = id }

    public var isActive: Bool { running > 0 }

    /// One line that is true whether the agent is busy or has been idle for days.
    public var headline: String {
        if running > 0 {
            var parts = [running == 1 ? "1 service running" : "\(running) services running"]
            if paused > 0 { parts.append("\(paused) paused") }
            if !ports.isEmpty { parts.append(Fmt.ports(ports)) }
            return parts.joined(separator: " · ")
        }
        if totalLaunched == 0 {
            return messageCount > 0 ? "no services — messages only" : "nothing recorded yet"
        }
        var parts = ["idle"]
        parts.append("\(totalLaunched) launched")
        if totalCrashed > 0 { parts.append("\(totalCrashed) crashed") }
        if totalLeaked > 0 { parts.append("\(totalLeaked) left running") }
        return parts.joined(separator: " · ")
    }

    /// How trustworthy this agent's cleanup has been, as a plain fraction.
    public var cleanupRecord: String {
        guard totalLaunched > 0 else { return "no launches yet" }
        let clean = totalLaunched - totalLeaked - totalCrashed
        return "\(clean) of \(totalLaunched) ended cleanly"
    }

    public var tone: AgentTone {
        if awaitingReply > 0 { return .waiting }
        if needingAttention > 0 || totalCrashed > 0 || totalLeaked > 0 { return .attention }
        if running > 0 { return .active }
        return .idle
    }

    public enum AgentTone: String, Codable, Sendable {
        case active, idle, waiting, attention
    }
}

public struct AgentSummary: Codable, Sendable, Identifiable, Hashable {
    public var id: String            // the agent name
    public var running: Int
    public var needingAttention: Int
    public var ports: [Int]
    public var oldestStart: Date?
    public var nextLeaseExpiry: Date?
    public var totalCPU: Double
    public var totalMemMB: Double
    /// Distinct purposes, so a summary line can say what the agent is doing.
    public var purposes: [String]
    public var awaitingReply: Int = 0
    public var lastMessageAt: Date?

    public init(id: String, running: Int = 0, needingAttention: Int = 0, ports: [Int] = [],
                oldestStart: Date? = nil, nextLeaseExpiry: Date? = nil, totalCPU: Double = 0,
                totalMemMB: Double = 0, purposes: [String] = []) {
        self.id = id
        self.running = running
        self.needingAttention = needingAttention
        self.ports = ports
        self.oldestStart = oldestStart
        self.nextLeaseExpiry = nextLeaseExpiry
        self.totalCPU = totalCPU
        self.totalMemMB = totalMemMB
        self.purposes = purposes
    }
}
