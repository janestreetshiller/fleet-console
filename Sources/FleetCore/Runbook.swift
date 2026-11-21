import Foundation

public struct RunbookParameter: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case port
        case serviceID
        case agentID
        case path
    }

    public var name: String
    public var kind: Kind
    public var prompt: String

    public var id: String { name }

    public init(name: String, kind: Kind, prompt: String) {
        self.name = name
        self.kind = kind
        self.prompt = prompt
    }
}

public enum RunbookEvidence: Codable, Sendable, Hashable {
    case managedServices
    case listenersOnPort(parameter: String)
    case processTable(top: Int)
    case diskUsage
    case reclaimCandidates
    case recentEvents(limit: Int)
    case serviceLog(parameter: String, lines: Int)
}

public enum RunbookTarget: Codable, Sendable, Hashable {
    case parameter(String)
    case each(RunbookQuery, max: Int)
}

public enum RunbookQuery: Codable, Sendable, Hashable {
    case leaseExpired
    case ownedBy(parameter: String)
    case listeningOnPort(parameter: String)
    case crashLooping(restartsAtLeast: Int)
}

public enum RunbookReclaimScope: String, Codable, Sendable, CaseIterable {
    case regeneratesFreely
}

public enum RunbookAction: Codable, Sendable, Hashable {
    case observe(RunbookEvidence)
    case stopService(RunbookTarget, reason: String)
    case renewLease(RunbookTarget, seconds: TimeInterval)
    case restartService(RunbookTarget)
    case reclaim(RunbookReclaimScope)
    case handOff(reason: String)

    public var isReadOnly: Bool {
        switch self {
        case .observe, .handOff: return true
        case .stopService, .renewLease, .restartService, .reclaim: return false
        }
    }

    public var target: RunbookTarget? {
        switch self {
        case .stopService(let target, _), .renewLease(let target, _), .restartService(let target):
            return target
        case .observe, .reclaim, .handOff:
            return nil
        }
    }
}

public enum RunbookApproval: String, Codable, Sendable, CaseIterable {
    case automatic
    case operatorApproval
}

public enum RunbookStop: String, Codable, Sendable, CaseIterable {
    case targetUnmanaged
    case tooManyTargets
    case evidenceUnavailable
    case approvalDenied
    case stepFailed
    case exhausted

    public var explanation: String {
        switch self {
        case .targetUnmanaged:
            return "The process involved is not one the controller started."
        case .tooManyTargets:
            return "More services matched than this runbook will act on at once."
        case .evidenceUnavailable:
            return "Something this runbook needs to see could not be read."
        case .approvalDenied:
            return "You declined a step."
        case .stepFailed:
            return "A step did not succeed, and the rest assumed it had."
        case .exhausted:
            return "Every step ran and the symptom is still here."
        }
    }
}

public struct RunbookStep: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var action: RunbookAction
    public var rationale: String
    public var approval: RunbookApproval

    public init(id: String, title: String, action: RunbookAction,
                rationale: String, approval: RunbookApproval) {
        self.id = id
        self.title = title
        self.action = action
        self.rationale = rationale
        self.approval = approval
    }

    public var isReadOnly: Bool { action.isReadOnly }
}

public struct Runbook: Codable, Sendable, Hashable, Identifiable {
    public static let currentFormat = 1

    public var id: String
    public var formatVersion: Int
    public var revision: Int
    public var title: String
    public var symptom: String
    public var briefing: String
    public var parameters: [RunbookParameter]
    public var evidence: [RunbookEvidence]
    public var steps: [RunbookStep]
    public var stopWhen: Set<RunbookStop>

    public init(id: String, formatVersion: Int = Runbook.currentFormat, revision: Int,
                title: String, symptom: String, briefing: String,
                parameters: [RunbookParameter] = [], evidence: [RunbookEvidence] = [],
                steps: [RunbookStep], stopWhen: Set<RunbookStop>) {
        self.id = id
        self.formatVersion = formatVersion
        self.revision = revision
        self.title = title
        self.symptom = symptom
        self.briefing = briefing
        self.parameters = parameters
        self.evidence = evidence
        self.steps = steps
        self.stopWhen = stopWhen
    }

    public var diagnosis: [RunbookStep] { steps.filter(\.isReadOnly) }

    public var mutations: [RunbookStep] { steps.filter { !$0.isReadOnly } }

    public var isAdvisoryOnly: Bool { mutations.isEmpty }

    public func parameter(named name: String) -> RunbookParameter? {
        parameters.first { $0.name == name }
    }
}
