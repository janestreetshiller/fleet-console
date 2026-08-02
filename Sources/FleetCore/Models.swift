import Foundation

// MARK: - Evidence
//
// The central honesty rule of FleetConsole: "reachable", "process exists",
// "port is listening" and "application health check passed" are four different
// facts. They are recorded separately, timestamped separately, and never
// collapsed into a single boolean anywhere in the codebase or the UI.

public struct Evidence: Codable, Sendable, Hashable {
    /// kill(pid, 0) succeeded *and* the process start time still matches the
    /// value recorded at launch (PID-reuse guard).
    public var processExists: Bool?
    /// Ports observed in LISTEN state for this service's process group.
    public var listeningPorts: [Int]
    /// Whether a port scan actually ran (distinguishes "no ports" from "not checked").
    public var portScanRan: Bool
    /// Whether a configured application health check ran, and its result.
    public var healthCheckRan: Bool
    public var healthPassed: Bool?
    public var healthDetail: String?
    public var healthLatencyMs: Double?
    public var checkedAt: Date?

    public init(processExists: Bool? = nil,
                listeningPorts: [Int] = [],
                portScanRan: Bool = false,
                healthCheckRan: Bool = false,
                healthPassed: Bool? = nil,
                healthDetail: String? = nil,
                healthLatencyMs: Double? = nil,
                checkedAt: Date? = nil) {
        self.processExists = processExists
        self.listeningPorts = listeningPorts
        self.portScanRan = portScanRan
        self.healthCheckRan = healthCheckRan
        self.healthPassed = healthPassed
        self.healthDetail = healthDetail
        self.healthLatencyMs = healthLatencyMs
        self.checkedAt = checkedAt
    }

    /// Evidence older than this many seconds must be rendered as "unknown (stale)".
    public func isStale(now: Date = Date(), tolerance: TimeInterval) -> Bool {
        guard let checkedAt else { return true }
        return now.timeIntervalSince(checkedAt) > tolerance
    }
}

// MARK: - Health

public enum HealthKind: String, Codable, Sendable, CaseIterable {
    case none       // no check configured — service can never be reported "healthy"
    case tcp        // TCP connect to host:port
    case http       // HTTP GET, expect a status code
}

public struct HealthSpec: Codable, Sendable, Hashable {
    public var kind: HealthKind
    /// http: full URL. tcp: "host:port".
    public var target: String?
    public var intervalSec: Double
    public var timeoutSec: Double
    public var expectStatus: Int
    /// Consecutive failures before the service is called unhealthy.
    public var failureThreshold: Int

    public init(kind: HealthKind = .none, target: String? = nil, intervalSec: Double = 15,
                timeoutSec: Double = 4, expectStatus: Int = 200, failureThreshold: Int = 3) {
        self.kind = kind
        self.target = target
        self.intervalSec = intervalSec
        self.timeoutSec = timeoutSec
        self.expectStatus = expectStatus
        self.failureThreshold = failureThreshold
    }
}

// MARK: - Budgets

public struct ResourceBudget: Codable, Sendable, Hashable {
    /// Hard ceiling on wall-clock runtime, independent of lease renewals.
    public var maxRuntimeSec: Double?
    public var cpuWarnPct: Double?
    public var memWarnMB: Double?
    /// Ports this service is allowed to listen on. Empty = declared ports only are expected,
    /// but nothing is enforced. A listener outside this set raises `portViolation`.
    public var allowedPorts: [Int]

    public init(maxRuntimeSec: Double? = nil, cpuWarnPct: Double? = nil,
                memWarnMB: Double? = nil, allowedPorts: [Int] = []) {
        self.maxRuntimeSec = maxRuntimeSec
        self.cpuWarnPct = cpuWarnPct
        self.memWarnMB = memWarnMB
        self.allowedPorts = allowedPorts
    }
}

// MARK: - Service state

public enum ServiceState: String, Codable, Sendable, CaseIterable {
    case starting
    case running        // process alive, no health check configured — "unverified"
    case healthy        // health check ran and passed
    case degraded       // alive + passing, but a budget threshold is breached
    case unhealthy      // health check ran and failed past its threshold
    case paused         // SIGSTOP — still resident, holding its ports, doing nothing
    case expiring       // lease nearly up
    case expired        // lease/max-runtime exceeded, reap pending
    case stopping
    case stopped
    case crashed        // exited without being asked to

    public var isTerminal: Bool {
        self == .stopped || self == .crashed
    }

    public var needsAttention: Bool {
        switch self {
        case .unhealthy, .crashed, .expired, .degraded: return true
        default: return false
        }
    }

    /// A paused process still holds its ports and memory — it is stopped in the
    /// scheduler sense only, which is a different thing from being stopped.
    public var isPaused: Bool { self == .paused }
}

public struct ResourceSample: Codable, Sendable, Hashable {
    public var cpuPct: Double?
    public var memMB: Double?
    /// Number of processes in the service's process group.
    public var processCount: Int
    public var sampledAt: Date?

    public init(cpuPct: Double? = nil, memMB: Double? = nil, processCount: Int = 0, sampledAt: Date? = nil) {
        self.cpuPct = cpuPct
        self.memMB = memMB
        self.processCount = processCount
        self.sampledAt = sampledAt
    }
}

/// The record the controller returns to an agent on launch, and the row the UI renders.
public struct ServiceRecord: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var friendlyName: String
    public var ownerAgent: String
    public var purpose: String

    public var command: [String]
    public var cwd: String
    /// Only the *keys* of any extra environment are stored — never the values (T6).
    public var envKeys: [String]

    public var pid: Int32?
    public var pgid: Int32?
    /// `ps -o lstart` of the pid at launch. Used to detect PID reuse before signalling.
    public var startSignature: String?

    public var declaredPorts: [Int]
    public var startedAt: Date
    public var leaseExpiresAt: Date
    public var leaseTTLSec: Double
    public var lastRenewedAt: Date?

    public var budget: ResourceBudget
    public var health: HealthSpec

    public var state: ServiceState
    public var evidence: Evidence
    public var resources: ResourceSample
    public var consecutiveHealthFailures: Int
    public var budgetBreaches: [String]

    public var restartCount: Int
    public var lastExitCode: Int32?
    public var stdoutPath: String
    public var stderrPath: String
    public var updatedAt: Date
    /// Recent CPU% and resident MB samples, newest last, for the row sparklines.
    /// Capped so a long-lived service cannot grow its own record without bound.
    public var cpuHistory: [Double] = []
    public var memHistory: [Double] = []
    public var pausedAt: Date?
    /// Set when the controller reaped this service because its lease or max
    /// runtime ran out — i.e. the owning agent walked away and left it running.
    /// Recorded on the row itself so an agent's leak count survives without
    /// re-reading the event log.
    public var reapedForExpiry = false
    /// Cumulative failed health checks over this service's life.
    public var healthFailureCount = 0
    /// True when this record was **claimed** from a process that was already
    /// running, rather than launched by the controller. The distinction is not
    /// cosmetic: the controller signals only what it started, so a claimed record
    /// is supervised and reported on but never stopped, reaped or restarted by it.
    public var claimed = false
    public var claimedAt: Date?

    public static let historyLimit = 40

    public init(id: String = UUID().uuidString,
                friendlyName: String,
                ownerAgent: String,
                purpose: String,
                command: [String],
                cwd: String,
                envKeys: [String] = [],
                pid: Int32? = nil,
                pgid: Int32? = nil,
                startSignature: String? = nil,
                declaredPorts: [Int] = [],
                startedAt: Date = Date(),
                leaseExpiresAt: Date,
                leaseTTLSec: Double,
                lastRenewedAt: Date? = nil,
                budget: ResourceBudget = ResourceBudget(),
                health: HealthSpec = HealthSpec(),
                state: ServiceState = .starting,
                evidence: Evidence = Evidence(),
                resources: ResourceSample = ResourceSample(),
                consecutiveHealthFailures: Int = 0,
                budgetBreaches: [String] = [],
                restartCount: Int = 0,
                lastExitCode: Int32? = nil,
                stdoutPath: String = "",
                stderrPath: String = "",
                updatedAt: Date = Date()) {
        self.id = id
        self.friendlyName = friendlyName
        self.ownerAgent = ownerAgent
        self.purpose = purpose
        self.command = command
        self.cwd = cwd
        self.envKeys = envKeys
        self.pid = pid
        self.pgid = pgid
        self.startSignature = startSignature
        self.declaredPorts = declaredPorts
        self.startedAt = startedAt
        self.leaseExpiresAt = leaseExpiresAt
        self.leaseTTLSec = leaseTTLSec
        self.lastRenewedAt = lastRenewedAt
        self.budget = budget
        self.health = health
        self.state = state
        self.evidence = evidence
        self.resources = resources
        self.consecutiveHealthFailures = consecutiveHealthFailures
        self.budgetBreaches = budgetBreaches
        self.restartCount = restartCount
        self.lastExitCode = lastExitCode
        self.stdoutPath = stdoutPath
        self.stderrPath = stderrPath
        self.updatedAt = updatedAt
    }

    /// Decoded field by field, with a default for everything that has one.
    ///
    /// The registry stores each record as a JSON blob, so the *only* schema
    /// migration this app has is what this initialiser tolerates. The synthesised
    /// decoder does not fall back to a property's default value — a missing key is
    /// a hard `keyNotFound` — so every field added after v1 (`cpuHistory`,
    /// `reapedForExpiry`, `healthFailureCount`, `claimed`, …) made every record
    /// written before it undecodable. The read path swallows that with `try?`, so
    /// the failure mode was not an error: it was terminal records quietly
    /// disappearing from the history on the first upgrade — the "stale records"
    /// row of the threat model, caused by us.
    ///
    /// Only the fields with no honest default are required.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        friendlyName = try c.decode(String.self, forKey: .friendlyName)
        ownerAgent = try c.decode(String.self, forKey: .ownerAgent)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        leaseExpiresAt = try c.decode(Date.self, forKey: .leaseExpiresAt)
        leaseTTLSec = try c.decode(Double.self, forKey: .leaseTTLSec)
        state = try c.decode(ServiceState.self, forKey: .state)

        purpose = try c.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        command = try c.decodeIfPresent([String].self, forKey: .command) ?? []
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        envKeys = try c.decodeIfPresent([String].self, forKey: .envKeys) ?? []
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        pgid = try c.decodeIfPresent(Int32.self, forKey: .pgid)
        startSignature = try c.decodeIfPresent(String.self, forKey: .startSignature)
        declaredPorts = try c.decodeIfPresent([Int].self, forKey: .declaredPorts) ?? []
        lastRenewedAt = try c.decodeIfPresent(Date.self, forKey: .lastRenewedAt)
        budget = try c.decodeIfPresent(ResourceBudget.self, forKey: .budget) ?? ResourceBudget()
        health = try c.decodeIfPresent(HealthSpec.self, forKey: .health) ?? HealthSpec()
        evidence = try c.decodeIfPresent(Evidence.self, forKey: .evidence) ?? Evidence()
        resources = try c.decodeIfPresent(ResourceSample.self, forKey: .resources) ?? ResourceSample()
        consecutiveHealthFailures = try c.decodeIfPresent(Int.self, forKey: .consecutiveHealthFailures) ?? 0
        budgetBreaches = try c.decodeIfPresent([String].self, forKey: .budgetBreaches) ?? []
        restartCount = try c.decodeIfPresent(Int.self, forKey: .restartCount) ?? 0
        lastExitCode = try c.decodeIfPresent(Int32.self, forKey: .lastExitCode)
        stdoutPath = try c.decodeIfPresent(String.self, forKey: .stdoutPath) ?? ""
        stderrPath = try c.decodeIfPresent(String.self, forKey: .stderrPath) ?? ""
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? startedAt
        cpuHistory = try c.decodeIfPresent([Double].self, forKey: .cpuHistory) ?? []
        memHistory = try c.decodeIfPresent([Double].self, forKey: .memHistory) ?? []
        pausedAt = try c.decodeIfPresent(Date.self, forKey: .pausedAt)
        reapedForExpiry = try c.decodeIfPresent(Bool.self, forKey: .reapedForExpiry) ?? false
        healthFailureCount = try c.decodeIfPresent(Int.self, forKey: .healthFailureCount) ?? 0
        claimed = try c.decodeIfPresent(Bool.self, forKey: .claimed) ?? false
        claimedAt = try c.decodeIfPresent(Date.self, forKey: .claimedAt)
    }

    public var shortID: String { String(id.prefix(8)) }
    public var commandLine: String { command.joined(separator: " ") }
    public var projectFolderName: String { (cwd as NSString).lastPathComponent }

    public var leaseRemaining: TimeInterval { leaseExpiresAt.timeIntervalSinceNow }
    public var uptime: TimeInterval { Date().timeIntervalSince(startedAt) }

    /// Ports we *see* listening, falling back to what was declared (clearly labelled in UI).
    public var effectivePorts: [Int] {
        evidence.listeningPorts.isEmpty ? declaredPorts : evidence.listeningPorts
    }

    /// True when the state was derived from a health check that actually ran.
    public var isVerified: Bool { evidence.healthCheckRan && evidence.healthPassed == true }

    /// Whether the *controller* may signal this record. False for anything it did
    /// not start, which is the one rule claiming does not buy its way out of: a
    /// claimed process gets an owner, a purpose, a lease and a timeline, and it
    /// still gets stopped by you rather than by the reaper.
    public var isSignallableByController: Bool { !claimed }

    /// Why a controller verb is refused on this record, or nil when it is allowed.
    public var signalRefusal: String? {
        guard claimed else { return nil }
        return "\(friendlyName) was claimed, not launched — the controller does not "
            + "signal processes it did not start. Stop it where you started it."
    }
}

// MARK: - Events (append-only)

public enum EventKind: String, Codable, Sendable, CaseIterable {
    case registered
    case claimed        // an already-running process was adopted into the registry
    case started
    case restarted
    case healthPassed
    case healthFailed
    case leaseRenewed
    case leaseExpiring
    case leaseExpired
    case maxRuntimeExceeded
    case budgetWarning
    case portViolation
    case stopRequested
    case stopping
    case stopped
    case paused
    case resumed
    case messagePosted
    case messageAnswered
    case crashed
    case reapIncomplete
    case pidReuseSuspected
    case reconcileMissing
    case becameUnmanaged
    case rejectedLaunch
    case rejectedPeer
    case daemonStarted
    case daemonStopping
    /// Written by the *next* generation on startup: a controller that dies through
    /// fatalError or SIGKILL never gets to record its own exit, so the only evidence is
    /// a `daemonStarted` with no `daemonStopping` after it.
    case daemonCrashed

    public var isBad: Bool {
        switch self {
        case .healthFailed, .crashed, .portViolation, .budgetWarning, .reapIncomplete,
             .pidReuseSuspected, .reconcileMissing, .becameUnmanaged, .rejectedLaunch,
             .rejectedPeer, .maxRuntimeExceeded, .leaseExpired, .daemonCrashed:
            return true
        default:
            return false
        }
    }

    public var label: String {
        switch self {
        case .registered: return "Registered"
        case .claimed: return "Claimed"
        case .started: return "Started"
        case .restarted: return "Restarted"
        case .healthPassed: return "Health check passed"
        case .healthFailed: return "Health check failed"
        case .leaseRenewed: return "Lease renewed"
        case .leaseExpiring: return "Lease expiring"
        case .leaseExpired: return "Lease expired"
        case .maxRuntimeExceeded: return "Max runtime exceeded"
        case .budgetWarning: return "Budget warning"
        case .portViolation: return "Port violation"
        case .stopRequested: return "Stop requested"
        case .stopping: return "Stopping"
        case .stopped: return "Stopped"
        case .paused: return "Paused"
        case .resumed: return "Resumed"
        case .messagePosted: return "Message posted"
        case .messageAnswered: return "Message answered"
        case .crashed: return "Crashed"
        case .reapIncomplete: return "Reap incomplete"
        case .pidReuseSuspected: return "PID reuse suspected"
        case .reconcileMissing: return "Process missing"
        case .becameUnmanaged: return "Became unmanaged"
        case .rejectedLaunch: return "Launch rejected"
        case .rejectedPeer: return "Peer rejected"
        case .daemonStarted: return "Controller started"
        case .daemonStopping: return "Controller stopping"
        case .daemonCrashed: return "Controller exited abnormally"
        }
    }
}

public struct ServiceEvent: Codable, Sendable, Identifiable, Hashable {
    public var seq: Int64
    public var serviceID: String?
    public var serviceName: String?
    public var ts: Date
    public var kind: EventKind
    public var detail: String
    /// Evidence snapshot captured at the moment the event was written.
    public var evidence: Evidence?

    public var id: Int64 { seq }

    public init(seq: Int64 = 0, serviceID: String? = nil, serviceName: String? = nil,
                ts: Date = Date(), kind: EventKind, detail: String, evidence: Evidence? = nil) {
        self.seq = seq
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.ts = ts
        self.kind = kind
        self.detail = detail
        self.evidence = evidence
    }
}

// MARK: - Unmanaged processes

public enum UnmanagedReason: String, Codable, Sendable {
    case listenerNotInRegistry
    case devServerShape
    case escapedProcessGroup   // declared port still held after its owning group died

    public var label: String {
        switch self {
        case .listenerNotInRegistry: return "Listening port with no registry record"
        case .devServerShape: return "Dev-server-shaped process, not launched via controller"
        case .escapedProcessGroup: return "Port still held after its managed group exited"
        }
    }
}

public struct UnmanagedProcess: Codable, Sendable, Identifiable, Hashable {
    public var id: String          // stable key: "pid:startsig"
    public var pid: Int32
    public var command: String     // executable name
    public var commandLine: String // full argv, truncated
    public var user: String
    public var ports: [Int]
    public var firstSeen: Date
    public var lastSeen: Date
    public var reason: UnmanagedReason
    /// Set when this process was once managed by us (strongest possible signal of a leak).
    public var formerServiceID: String?

    public init(id: String, pid: Int32, command: String, commandLine: String, user: String,
                ports: [Int], firstSeen: Date, lastSeen: Date, reason: UnmanagedReason,
                formerServiceID: String? = nil) {
        self.id = id
        self.pid = pid
        self.command = command
        self.commandLine = commandLine
        self.user = user
        self.ports = ports
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.reason = reason
        self.formerServiceID = formerServiceID
    }
}

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

// MARK: - Host metrics

public struct HostMetrics: Codable, Sendable, Hashable {
    public var cpuPct: Double?
    public var memUsedGB: Double?
    public var memTotalGB: Double?
    public var diskUsedGB: Double?
    public var diskTotalGB: Double?
    public var gpuPct: Double?
    public var collectedAt: Date?

    public init(cpuPct: Double? = nil, memUsedGB: Double? = nil, memTotalGB: Double? = nil,
                diskUsedGB: Double? = nil, diskTotalGB: Double? = nil, gpuPct: Double? = nil,
                collectedAt: Date? = nil) {
        self.cpuPct = cpuPct
        self.memUsedGB = memUsedGB
        self.memTotalGB = memTotalGB
        self.diskUsedGB = diskUsedGB
        self.diskTotalGB = diskTotalGB
        self.gpuPct = gpuPct
        self.collectedAt = collectedAt
    }

    public var hasAny: Bool {
        cpuPct != nil || memUsedGB != nil || diskUsedGB != nil
    }

    public var line: String {
        var parts: [String] = []
        if let cpuPct { parts.append(String(format: "CPU %.0f%%", cpuPct)) }
        if let memUsedGB, let memTotalGB {
            parts.append(String(format: "RAM %.1f/%.0f GB", memUsedGB, memTotalGB))
        }
        if let diskUsedGB, let diskTotalGB {
            parts.append(String(format: "SSD %.0f/%.0f GB", diskUsedGB, diskTotalGB))
        }
        if let gpuPct { parts.append(String(format: "GPU %.0f%%", gpuPct)) }
        return parts.isEmpty ? "no metrics" : parts.joined(separator: " · ")
    }
}

// MARK: - Local tools
//
// Long-lived tools you run yourself — a dashboard, an inference server, a driver.
// They are not launched through the controller and never will be, but they are
// not "unmanaged" in the sense of a leak either: you meant them to be there.
// Declaring them turns anonymous noise into an inventory, and it means their own
// menu-bar apps have nothing left to tell you.

public struct ExternalService: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var symbol: String
    public var running: Bool
    public var pid: Int32?
    public var ports: [Int]
    public var declaredPorts: [Int]
    public var commandLine: String?
    /// Opened when you click the row, if it has a UI.
    public var url: String?
    public var startedAt: Date?
    public var checkedAt: Date

    public init(id: String, name: String, symbol: String = "wrench.and.screwdriver",
                running: Bool = false, pid: Int32? = nil, ports: [Int] = [],
                declaredPorts: [Int] = [], commandLine: String? = nil, url: String? = nil,
                startedAt: Date? = nil, checkedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.running = running
        self.pid = pid
        self.ports = ports
        self.declaredPorts = declaredPorts
        self.commandLine = commandLine
        self.url = url
        self.startedAt = startedAt
        self.checkedAt = checkedAt
    }

    public var summary: String {
        guard running else { return "not running" }
        var parts: [String] = []
        if !ports.isEmpty { parts.append(Fmt.ports(ports)) }
        if let pid { parts.append("pid \(pid)") }
        if let startedAt { parts.append("up \(Fmt.duration(Date().timeIntervalSince(startedAt)))") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Devices

public struct DeviceEvidence: Codable, Sendable, Hashable {
    public var icmpOK: Bool?
    public var icmpRTTms: Double?
    public var tcpOK: Bool?
    public var tcpPort: Int?
    public var tailscaleOnline: Bool?
    public var tailscaleLastSeen: Date?
    public var checkedAt: Date?
    public var isSelf: Bool

    public init(icmpOK: Bool? = nil, icmpRTTms: Double? = nil, tcpOK: Bool? = nil,
                tcpPort: Int? = nil, tailscaleOnline: Bool? = nil, tailscaleLastSeen: Date? = nil,
                checkedAt: Date? = nil, isSelf: Bool = false) {
        self.icmpOK = icmpOK
        self.icmpRTTms = icmpRTTms
        self.tcpOK = tcpOK
        self.tcpPort = tcpPort
        self.tailscaleOnline = tailscaleOnline
        self.tailscaleLastSeen = tailscaleLastSeen
        self.checkedAt = checkedAt
        self.isSelf = isSelf
    }

    /// Reachability is only claimed when a probe actually succeeded.
    public var reachable: Bool? {
        if icmpOK == true || tcpOK == true { return true }
        if icmpOK == nil && tcpOK == nil { return nil }
        if icmpOK == false && tcpOK == false { return false }
        return nil
    }
}

public enum DeviceHealth: String, Codable, Sendable {
    case reachable      // a probe succeeded
    case partial        // some probes succeeded, others failed
    case unreachable    // probes ran and all failed
    case unknown        // no probe has completed yet

    public var label: String {
        switch self {
        case .reachable: return "Reachable"
        case .partial: return "Partially reachable"
        case .unreachable: return "Unreachable"
        case .unknown: return "Unknown"
        }
    }
}

public struct DeviceRecord: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var model: String
    /// LAN hostname or IP, optional.
    public var localHost: String?
    /// Tailscale DNS name or magic-DNS short name.
    public var tailscaleHost: String?
    public var tailscaleIP: String?
    public var localIP: String?
    /// TCP port used as a reachability probe (e.g. 22).
    public var probePort: Int?
    public var evidence: DeviceEvidence
    public var lastReachableAt: Date?
    /// Services managed by *that* machine's controller, fetched read-only over SSH.
    /// FleetConsole never controls a remote process — it only reports one.
    public var remoteServices: [ServiceRecord] = []
    public var remoteError: String?
    public var remoteCheckedAt: Date?
    /// CPU / RAM / SSD for this machine — what the AI-Pocket badge used to show.
    public var metrics: HostMetrics = HostMetrics()

    public init(id: String, name: String, model: String = "", localHost: String? = nil,
                tailscaleHost: String? = nil, tailscaleIP: String? = nil, localIP: String? = nil,
                probePort: Int? = 22, evidence: DeviceEvidence = DeviceEvidence(),
                lastReachableAt: Date? = nil) {
        self.id = id
        self.name = name
        self.model = model
        self.localHost = localHost
        self.tailscaleHost = tailscaleHost
        self.tailscaleIP = tailscaleIP
        self.localIP = localIP
        self.probePort = probePort
        self.evidence = evidence
        self.lastReachableAt = lastReachableAt
    }

    public var health: DeviceHealth {
        if evidence.isSelf { return .reachable }
        let e = evidence
        let results = [e.icmpOK, e.tcpOK, e.tailscaleOnline].compactMap { $0 }
        if results.isEmpty { return .unknown }
        if results.allSatisfy({ $0 }) { return .reachable }
        if results.contains(true) { return .partial }
        return .unreachable
    }
}

// MARK: - Attention

public enum AttentionSeverity: String, Codable, Sendable {
    case critical, warning
}

public struct AttentionItem: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var severity: AttentionSeverity
    public var title: String
    public var detail: String
    public var serviceID: String?
    public var unmanagedID: String?
    public var since: Date

    public init(id: String, severity: AttentionSeverity, title: String, detail: String,
                serviceID: String? = nil, unmanagedID: String? = nil, since: Date = Date()) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.serviceID = serviceID
        self.unmanagedID = unmanagedID
        self.since = since
    }
}

// MARK: - Snapshot

public struct DaemonInfo: Codable, Sendable, Hashable {
    public var version: String
    public var pid: Int32
    public var startedAt: Date
    public var lastTickAt: Date?
    public var lastReconcileAt: Date?
    public var tickIntervalSec: Double
    public var socketPath: String

    public init(version: String, pid: Int32, startedAt: Date, lastTickAt: Date? = nil,
                lastReconcileAt: Date? = nil, tickIntervalSec: Double = 5, socketPath: String = "") {
        self.version = version
        self.pid = pid
        self.startedAt = startedAt
        self.lastTickAt = lastTickAt
        self.lastReconcileAt = lastReconcileAt
        self.tickIntervalSec = tickIntervalSec
        self.socketPath = socketPath
    }

    public var uptime: TimeInterval { Date().timeIntervalSince(startedAt) }
}

public struct Snapshot: Codable, Sendable {
    public var generatedAt: Date
    public var daemon: DaemonInfo
    public var services: [ServiceRecord]
    public var unmanaged: [UnmanagedProcess]
    public var devices: [DeviceRecord]
    public var attention: [AttentionItem]
    public var recentEvents: [ServiceEvent]
    public var messages: [AgentMessage] = []
    public var external: [ExternalService] = []
    public var sessions: [AgentSession] = []

    public init(generatedAt: Date = Date(), daemon: DaemonInfo, services: [ServiceRecord] = [],
                unmanaged: [UnmanagedProcess] = [], devices: [DeviceRecord] = [],
                attention: [AttentionItem] = [], recentEvents: [ServiceEvent] = [],
                messages: [AgentMessage] = [], external: [ExternalService] = [],
                sessions: [AgentSession] = []) {
        self.messages = messages
        self.external = external
        self.sessions = sessions
        self.generatedAt = generatedAt
        self.daemon = daemon
        self.services = services
        self.unmanaged = unmanaged
        self.devices = devices
        self.attention = attention
        self.recentEvents = recentEvents
    }

    public var activeServices: [ServiceRecord] { services.filter { !$0.state.isTerminal } }
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

extension Snapshot {
    /// Derived on the client so both the CLI and the app show the same thing
    /// without adding another server round trip.
    public var agentSummaries: [AgentSummary] {
        let live = services.filter { !$0.state.isTerminal }
        let byAgent = Dictionary(grouping: live, by: \.ownerAgent)
        let messagesByAgent = Dictionary(grouping: messages, by: \.agent)
        // An agent with no services but an unanswered question still needs to
        // appear — that is precisely the case you must not miss.
        let names = Set(byAgent.keys).union(messagesByAgent.keys)

        return names.map { agent in
            let records = byAgent[agent] ?? []
            let mail = messagesByAgent[agent] ?? []
            var summary = AgentSummary(
                id: agent,
                running: records.count,
                needingAttention: records.filter { $0.state.needsAttention }.count,
                ports: Array(Set(records.flatMap(\.effectivePorts))).sorted(),
                oldestStart: records.map(\.startedAt).min(),
                nextLeaseExpiry: records.map(\.leaseExpiresAt).min(),
                totalCPU: records.compactMap { $0.resources.cpuPct }.reduce(0, +),
                totalMemMB: records.compactMap { $0.resources.memMB }.reduce(0, +),
                purposes: Array(Set(records.map(\.purpose))).sorted())
            summary.awaitingReply = mail.filter(\.isAwaitingReply).count
            summary.lastMessageAt = mail.map(\.createdAt).max()
            return summary
        }
        .sorted {
            ($0.awaitingReply, $0.needingAttention, $0.running)
                > ($1.awaitingReply, $1.needingAttention, $1.running)
        }
    }

    public var awaitingReplyCount: Int { messages.filter(\.isAwaitingReply).count }

    /// The full picture for one agent, including everything it has *done* — not
    /// just what it happens to be running this second. An idle agent still has a
    /// history worth showing; "0 services" on its own says nothing.
    public var agentProfiles: [AgentProfile] {
        let byAgent = Dictionary(grouping: services, by: \.ownerAgent)
        let messagesByAgent = Dictionary(grouping: messages, by: \.agent)
        let names = Set(byAgent.keys).union(messagesByAgent.keys)

        return names.map { name in
            let all = byAgent[name] ?? []
            let live = all.filter { !$0.state.isTerminal }
            let mail = (messagesByAgent[name] ?? []).sorted { $0.createdAt > $1.createdAt }

            var profile = AgentProfile(id: name)
            profile.running = live.count
            profile.paused = live.filter { $0.state == .paused }.count
            profile.needingAttention = live.filter { $0.state.needsAttention }.count
            profile.ports = Array(Set(live.flatMap(\.effectivePorts))).sorted()
            profile.cpuPct = live.compactMap { $0.resources.cpuPct }.reduce(0, +)
            profile.memMB = live.compactMap { $0.resources.memMB }.reduce(0, +)
            profile.nextLeaseExpiry = live.map(\.leaseExpiresAt).min()

            profile.totalLaunched = all.count
            profile.totalStopped = all.filter { $0.state == .stopped }.count
            profile.totalCrashed = all.filter { $0.state == .crashed }.count
            profile.totalLeaked = all.filter(\.reapedForExpiry).count
            profile.totalRestarts = all.reduce(0) { $0 + $1.restartCount }
            profile.healthFailures = all.reduce(0) { $0 + $1.healthFailureCount }
            profile.totalRuntime = all.reduce(0) { total, record in
                total + (record.state.isTerminal
                         ? record.updatedAt.timeIntervalSince(record.startedAt)
                         : Date().timeIntervalSince(record.startedAt))
            }

            profile.firstSeen = all.map(\.startedAt).min()
            profile.lastActivityAt = [all.map(\.updatedAt).max(), mail.first?.createdAt]
                .compactMap { $0 }.max()
            profile.projects = Array(Set(all.map(\.cwd))).sorted()
            profile.purposes = Array(Set(live.map(\.purpose))).sorted()
            profile.recentServices = all.sorted { $0.startedAt > $1.startedAt }.prefix(5).map { $0 }

            profile.messageCount = mail.count
            profile.awaitingReply = mail.filter(\.isAwaitingReply).count
            profile.lastMessage = mail.first
            return profile
        }
        .sorted {
            ($0.awaitingReply, $0.needingAttention, $0.running, $0.totalLaunched)
                > ($1.awaitingReply, $1.needingAttention, $1.running, $1.totalLaunched)
        }
    }
}

// MARK: - Formatting helpers shared by CLI and UI

public enum Fmt {
    public static func duration(_ seconds: TimeInterval, compact: Bool = true) -> String {
        let s = Int(abs(seconds.rounded()))
        if s < 60 { return "\(s)s" }
        let m = s / 60, h = m / 60, d = h / 24
        if m < 60 { return compact ? "\(m)m" : "\(m)m \(s % 60)s" }
        if h < 24 { return compact ? "\(h)h \(m % 60)m" : "\(h)h \(m % 60)m" }
        return "\(d)d \(h % 24)h"
    }

    public static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "never" }
        let delta = now.timeIntervalSince(date)
        if delta < -1 { return "in \(duration(-delta))" }
        if delta < 2 { return "just now" }
        return "\(duration(delta)) ago"
    }

    public static func ports(_ ports: [Int]) -> String {
        ports.isEmpty ? "—" : ports.sorted().map { ":\($0)" }.joined(separator: " ")
    }

    public static func mem(_ mb: Double?) -> String {
        guard let mb else { return "—" }
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }

    public static func cpu(_ pct: Double?) -> String {
        guard let pct else { return "—" }
        return String(format: "%.1f%%", pct)
    }
}
