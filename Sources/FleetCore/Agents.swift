import Foundation

public enum AgentTurn: String, Codable, Sendable {
    case assistant
    case user
    case tool

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
    public var project: String?
    public var startedAt: Date?
    public var cpuPct: Double
    public var memMB: Double
    public var commandLine: String

    public var sessionUID: String?
    public var sessionName: String?
    public var transcriptPath: String?
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

    public var previewAge: String? {
        guard let previewAt, let previewTurn else { return nil }
        return "\(previewTurn.label) \(Fmt.relative(previewAt))"
    }
}

public enum MessageKind: String, Codable, Sendable, CaseIterable {
    case status
    case question
    case problem

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
    public var needsReply: Bool
    public var reply: String?
    public var repliedAt: Date?
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

public struct AgentProfile: Codable, Sendable, Identifiable, Hashable {
    public var id: String

    public var owned = 0
    public var running = 0
    public var paused = 0
    public var needingAttention = 0
    public var ports: [Int] = []
    public var cpuPct: Double = 0
    public var memMB: Double = 0
    public var nextLeaseExpiry: Date?

    public var totalLaunched = 0
    public var totalStopped = 0
    public var totalCrashed = 0
    public var totalLeaked = 0
    public var totalRestarts = 0
    public var healthFailures = 0
    public var totalRuntime: TimeInterval = 0
    public var firstSeen: Date?
    public var lastActivityAt: Date?
    public var projects: [String] = []
    public var purposes: [String] = []
    public var recentServices: [ServiceRecord] = []

    public var messageCount = 0
    public var awaitingReply = 0
    public var lastMessage: AgentMessage?

    public init(id: String) { self.id = id }

    public var isActive: Bool { running > 0 }

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
    public var id: String
    public var owned: Int = 0
    public var running: Int
    public var needingAttention: Int
    public var ports: [Int]
    public var oldestStart: Date?
    public var nextLeaseExpiry: Date?
    public var totalCPU: Double
    public var totalMemMB: Double
    public var purposes: [String]
    public var awaitingReply: Int = 0
    public var lastMessageAt: Date?

    public init(id: String, owned: Int = 0, running: Int = 0, needingAttention: Int = 0,
                ports: [Int] = [], oldestStart: Date? = nil, nextLeaseExpiry: Date? = nil,
                totalCPU: Double = 0, totalMemMB: Double = 0, purposes: [String] = []) {
        self.id = id
        self.owned = owned
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
