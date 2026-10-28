import Foundation

// The append-only event log's vocabulary. Every state change files one of these,
// and the log outlives the records it describes — `prune` drops terminal service
// rows and never touches events.
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
