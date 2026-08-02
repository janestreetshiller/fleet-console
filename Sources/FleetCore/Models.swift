import Foundation

// A service as the controller knows it: what it is, what evidence there is that
// it is alive, and what it is allowed to consume.
//
// Split out of a single 1,158-line Models.swift. That file was one `import` and
// eleven unrelated subjects, so "where is the record type" and "where is the
// message type" had the same answer. These files are those subjects. Nothing here
// changed except which file it sits in — the types, their members and their
// comments are the originals.
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
