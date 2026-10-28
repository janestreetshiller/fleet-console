import Foundation

/// Newline-delimited JSON over a 0600 Unix domain socket. There is no network
/// listener anywhere in FleetConsole (threat model T5).
public enum RPCOp: String, Codable, Sendable {
    case ping
    case snapshot
    case subscribe      // server pushes a Snapshot per state change / tick
    case launch
    case renew
    case stop
    case restart
    case events
    case logs
    case claim          // adopt an already-running unmanaged process into the registry
    case reconcile      // force an immediate reconciliation sweep
    case refreshDevices
    case reloadConfig
    case ignoreCommand  // add a command to the expected-listener allow-list
    case prune          // drop terminal service records (never events)
    case pause          // SIGSTOP the process group
    case resume         // SIGCONT the process group
    case kill           // SIGKILL immediately, no grace period
    case postMessage    // an agent says something to the operator
    case messages       // read the mailbox
    case reply          // the operator answers a message
    case markSeen       // mark messages as seen so notifications fire once
}

/// A request from an agent to run something. This is the *only* way a process
/// enters the registry.
public struct LaunchRequest: Codable, Sendable {
    public var friendlyName: String
    public var ownerAgent: String
    public var purpose: String
    public var command: [String]
    public var cwd: String
    /// Extra environment. Values are used for the spawn but never persisted (T6).
    public var env: [String: String]
    public var declaredPorts: [Int]
    public var leaseTTLSec: Double
    public var budget: ResourceBudget
    public var health: HealthSpec

    public init(friendlyName: String, ownerAgent: String, purpose: String, command: [String],
                cwd: String, env: [String: String] = [:], declaredPorts: [Int] = [],
                leaseTTLSec: Double = 3600, budget: ResourceBudget = ResourceBudget(),
                health: HealthSpec = HealthSpec()) {
        self.friendlyName = friendlyName
        self.ownerAgent = ownerAgent
        self.purpose = purpose
        self.command = command
        self.cwd = cwd
        self.env = env
        self.declaredPorts = declaredPorts
        self.leaseTTLSec = leaseTTLSec
        self.budget = budget
        self.health = health
    }
}

public struct RPCRequest: Codable, Sendable {
    public var op: RPCOp
    public var launch: LaunchRequest?
    public var serviceID: String?
    public var ttlSec: Double?
    public var limit: Int?
    public var stream: String?      // "out" | "err"
    public var maxBytes: Int?
    /// Free-text reason recorded in the event log for mutating operations.
    public var reason: String?
    /// Executable name for `ignoreCommand`.
    public var command: String?
    /// `UnmanagedProcess.id` (or a bare pid) for `claim`.
    public var unmanagedID: String?
    /// Human name to file a claimed process under. Defaults to its executable.
    public var friendlyName: String?
    /// Why a claimed process is allowed to exist. Recorded on the record, not just
    /// in the event log, which is what separates it from `reason`.
    public var purpose: String?
    /// The owning agent, for `postMessage`, `messages` — and for `claim`, where it
    /// is who is answering for the process from now on.
    public var agent: String?
    public var body: String?
    public var kind: MessageKind?
    public var needsReply: Bool?
    public var messageID: Int64?
    public var unansweredOnly: Bool?

    public init(op: RPCOp, launch: LaunchRequest? = nil, serviceID: String? = nil,
                ttlSec: Double? = nil, limit: Int? = nil, stream: String? = nil,
                maxBytes: Int? = nil, reason: String? = nil, command: String? = nil,
                unmanagedID: String? = nil, friendlyName: String? = nil,
                purpose: String? = nil,
                agent: String? = nil, body: String? = nil, kind: MessageKind? = nil,
                needsReply: Bool? = nil, messageID: Int64? = nil, unansweredOnly: Bool? = nil) {
        self.unmanagedID = unmanagedID
        self.friendlyName = friendlyName
        self.purpose = purpose
        self.agent = agent
        self.body = body
        self.kind = kind
        self.needsReply = needsReply
        self.messageID = messageID
        self.unansweredOnly = unansweredOnly
        self.op = op
        self.launch = launch
        self.serviceID = serviceID
        self.ttlSec = ttlSec
        self.limit = limit
        self.stream = stream
        self.maxBytes = maxBytes
        self.reason = reason
        self.command = command
    }
}

public struct LogChunk: Codable, Sendable {
    public var serviceID: String
    public var stream: String
    public var path: String
    public var bytes: Int
    public var text: String
    public var truncated: Bool

    public init(serviceID: String, stream: String, path: String, bytes: Int, text: String, truncated: Bool) {
        self.serviceID = serviceID
        self.stream = stream
        self.path = path
        self.bytes = bytes
        self.text = text
        self.truncated = truncated
    }
}

public struct RPCResponse: Codable, Sendable {
    public var ok: Bool
    public var error: String?
    public var snapshot: Snapshot?
    public var service: ServiceRecord?
    public var events: [ServiceEvent]?
    public var logs: LogChunk?
    public var daemon: DaemonInfo?
    public var messages: [AgentMessage]?
    public var message: AgentMessage?

    public init(ok: Bool, error: String? = nil, snapshot: Snapshot? = nil,
                service: ServiceRecord? = nil, events: [ServiceEvent]? = nil,
                logs: LogChunk? = nil, daemon: DaemonInfo? = nil,
                messages: [AgentMessage]? = nil, message: AgentMessage? = nil) {
        self.messages = messages
        self.message = message
        self.ok = ok
        self.error = error
        self.snapshot = snapshot
        self.service = service
        self.events = events
        self.logs = logs
        self.daemon = daemon
    }

    public static func failure(_ message: String) -> RPCResponse {
        RPCResponse(ok: false, error: message)
    }
}
