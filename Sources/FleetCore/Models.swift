import Foundation

public struct Evidence: Codable, Sendable, Hashable {
    public var processExists: Bool?
    public var listeningPorts: [Int]
    public var portScanRan: Bool
    public var healthCheckRan: Bool
    public var healthPassed: Bool?
    public var healthDetail: String?
    public var healthLatencyMs: Double?
    public var checkedAt: Date?
    public var leaderVerifiedAt: Date?

    public init(processExists: Bool? = nil,
                listeningPorts: [Int] = [],
                portScanRan: Bool = false,
                healthCheckRan: Bool = false,
                healthPassed: Bool? = nil,
                healthDetail: String? = nil,
                healthLatencyMs: Double? = nil,
                checkedAt: Date? = nil,
                leaderVerifiedAt: Date? = nil) {
        self.processExists = processExists
        self.listeningPorts = listeningPorts
        self.portScanRan = portScanRan
        self.healthCheckRan = healthCheckRan
        self.healthPassed = healthPassed
        self.healthDetail = healthDetail
        self.healthLatencyMs = healthLatencyMs
        self.checkedAt = checkedAt
        self.leaderVerifiedAt = leaderVerifiedAt
    }

    public func isStale(now: Date = Date(), tolerance: TimeInterval) -> Bool {
        guard let checkedAt else { return true }
        return now.timeIntervalSince(checkedAt) > tolerance
    }
}

public enum HealthKind: String, Codable, Sendable, CaseIterable {
    case none
    case tcp
    case http
}

public struct HealthSpec: Codable, Sendable, Hashable {
    public var kind: HealthKind
    public var target: String?
    public var intervalSec: Double
    public var timeoutSec: Double
    public var expectStatus: Int
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

public struct ResourceBudget: Codable, Sendable, Hashable {
    public var maxRuntimeSec: Double?
    public var cpuWarnPct: Double?
    public var memWarnMB: Double?
    public var allowedPorts: [Int]

    public init(maxRuntimeSec: Double? = nil, cpuWarnPct: Double? = nil,
                memWarnMB: Double? = nil, allowedPorts: [Int] = []) {
        self.maxRuntimeSec = maxRuntimeSec
        self.cpuWarnPct = cpuWarnPct
        self.memWarnMB = memWarnMB
        self.allowedPorts = allowedPorts
    }
}

public enum ServiceState: String, Codable, Sendable, CaseIterable {
    case starting
    case running
    case healthy
    case degraded
    case unhealthy
    case paused
    case expiring
    case expired
    case stopping
    case stopped
    case crashed

    public var isTerminal: Bool {
        self == .stopped || self == .crashed
    }

    public var isRunning: Bool {
        switch self {
        case .starting, .running, .healthy, .degraded, .unhealthy, .paused, .expiring:
            return true
        case .expired, .stopping, .stopped, .crashed:
            return false
        }
    }

    public var needsAttention: Bool {
        switch self {
        case .unhealthy, .crashed, .expired, .degraded: return true
        default: return false
        }
    }

    public var isPaused: Bool { self == .paused }
}

public struct ResourceSample: Codable, Sendable, Hashable {
    public var cpuPct: Double?
    public var memMB: Double?
    public var processCount: Int
    public var sampledAt: Date?

    public init(cpuPct: Double? = nil, memMB: Double? = nil, processCount: Int = 0, sampledAt: Date? = nil) {
        self.cpuPct = cpuPct
        self.memMB = memMB
        self.processCount = processCount
        self.sampledAt = sampledAt
    }
}

public struct ServiceRecord: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var friendlyName: String
    public var ownerAgent: String
    public var purpose: String

    public var command: [String]
    public var cwd: String
    public var envKeys: [String]

    public var pid: Int32?
    public var pgid: Int32?
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
    public var cpuHistory: [Double] = []
    public var memHistory: [Double] = []
    public var pausedAt: Date?
    public var reapedForExpiry = false
    public var healthFailureCount = 0
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
    public var uptime: TimeInterval {
        let end = state.isTerminal ? updatedAt : Date()
        return max(0, end.timeIntervalSince(startedAt))
    }

    public var effectivePorts: [Int] {
        evidence.listeningPorts.isEmpty ? declaredPorts : evidence.listeningPorts
    }

    public var isVerified: Bool { evidence.healthCheckRan && evidence.healthPassed == true }

    public var isSignallableByController: Bool { !claimed }

    package func leaderVerification(in table: ProcessTable) -> Date? {
        guard !table.processProbeFailed,
              let pid, pid > 0, pid == pgid,
              let startSignature, !startSignature.isEmpty,
              let proc = table.process(pid), proc.pid == pid, proc.pgid == pid,
              proc.startSignature == startSignature else { return nil }
        return table.capturedAt
    }

    public var signalRefusal: String? {
        guard claimed else { return nil }
        return "\(friendlyName) was claimed, not launched — the controller does not "
            + "signal processes it did not start. Stop it where you started it."
    }
}
