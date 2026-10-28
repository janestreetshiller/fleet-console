import Foundation

// Runbooks: what a model is allowed to do about one situation.
//
// A runbook is a versioned document written by a developer, shipped alongside a
// model, and read by the operator before anything happens. It says what symptom
// it addresses, what evidence to gather, what steps may be taken in what order,
// which of those need a human, and when to stop and hand back.
//
// ## The one decision everything else follows from
//
// **A step is a typed action from a closed vocabulary, never a command string.**
//
// The obvious design is `command: String` with the model filling in the blanks.
// That design is a remote shell with extra steps: the blast radius is whatever
// the model can spell, and no amount of prompting narrows it. Here the set of
// things any runbook can express is fixed by `RunbookAction` at compile time, so
// the worst a malicious or confused document can ask for is something already on
// the list — and everything on the list goes through `fleetctl`, which means
// leases, reaping and the event log apply to it unchanged.
//
// The cost is real: a situation nobody anticipated cannot be automated until the
// vocabulary grows, and growing it is a code change with a review. That is the
// trade, and it is the right way round for software that touches other people's
// machines.
//
// Everything in this file is pure data. Executing a runbook is `RunbookEngine`'s
// job and does not exist yet; validating one is `RunbookValidation`.

// MARK: - Parameters

/// An input the runbook needs before it can do anything — the port that is
/// taken, the agent that went quiet. Supplied by the operator or proposed by the
/// model from evidence; either way it is named here first, so a step can never
/// reference a value the document did not declare.
public struct RunbookParameter: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case port
        case serviceID
        case agentID
        case path
    }

    public var name: String
    public var kind: Kind
    /// What the operator is asked, in their words. Shown verbatim.
    public var prompt: String

    public var id: String { name }

    public init(name: String, kind: Kind, prompt: String) {
        self.name = name
        self.kind = kind
        self.prompt = prompt
    }
}

// MARK: - Evidence

/// A read-only question about the machine. Gathering evidence changes nothing,
/// which is what lets the whole diagnosis phase run without an approval gate.
public enum RunbookEvidence: Codable, Sendable, Hashable {
    /// The controller's registry: what it owns and the state of each lease.
    case managedServices
    /// Who is listening on the port named by a parameter.
    case listenersOnPort(parameter: String)
    /// The heaviest processes on the machine, by CPU and by memory.
    case processTable(top: Int)
    /// Volume capacity and what is using it.
    case diskUsage
    /// Space that regenerates on its own, and what it costs to lose.
    case reclaimCandidates
    /// The append-only log, most recent first.
    case recentEvents(limit: Int)
    /// One service's stdout, tail only.
    case serviceLog(parameter: String, lines: Int)
}

// MARK: - Targets

/// Which services a mutating step acts on.
///
/// There is no "everything" case, and there never will be. `each` carries a
/// mandatory cap because an uncapped multi-target mutation is the shape that
/// stops a whole fleet from one bad match — the cap is what turns a runaway into
/// a bounded action the operator can read before approving.
public enum RunbookTarget: Codable, Sendable, Hashable {
    /// Exactly the one service named by a parameter.
    case parameter(String)
    /// Every service the query matches, up to `max`.
    case each(RunbookQuery, max: Int)
}

/// The closed set of ways a runbook may select services it did not name.
public enum RunbookQuery: Codable, Sendable, Hashable {
    /// Past its lease and still running — the leaked-daemon case.
    case leaseExpired
    /// Owned by the agent named by a parameter.
    case ownedBy(parameter: String)
    /// Holding the port named by a parameter.
    case listeningOnPort(parameter: String)
    /// Restarted more times than a healthy service would.
    case crashLooping(restartsAtLeast: Int)
}

/// What a reclaim step is allowed to remove.
///
/// One case, deliberately. Everything else the storage scanner finds — a model
/// weight, a photo library, anything that does not come back on its own — is
/// reported to the operator and never offered to a runbook. A ceiling with a
/// second rung would eventually be raised.
public enum RunbookReclaimScope: String, Codable, Sendable, CaseIterable {
    /// Caches that regenerate transparently, costing nothing but a slower next build.
    case regeneratesFreely
}

// MARK: - Actions

/// Everything a runbook step can be. The list is the safety boundary.
public enum RunbookAction: Codable, Sendable, Hashable {
    /// Gather evidence. Changes nothing.
    case observe(RunbookEvidence)
    /// Ask the controller to stop a service it owns.
    case stopService(RunbookTarget, reason: String)
    /// Extend a lease rather than let the reaper take it.
    case renewLease(RunbookTarget, seconds: TimeInterval)
    /// Stop and start again, through the controller.
    case restartService(RunbookTarget)
    /// Delete space that regenerates on its own.
    case reclaim(RunbookReclaimScope)
    /// Stop here and give the operator the floor, with a reason they can read.
    case handOff(reason: String)

    /// Whether the step leaves the machine exactly as it found it.
    ///
    /// This drives the approval invariant and the read-only diagnosis pass, so
    /// the switch is exhaustive on purpose: a new action must be classified
    /// deliberately rather than inheriting a default.
    public var isReadOnly: Bool {
        switch self {
        case .observe, .handOff: return true
        case .stopService, .renewLease, .restartService, .reclaim: return false
        }
    }

    /// The services this action touches, if any. `nil` for actions that do not
    /// act on a service at all.
    public var target: RunbookTarget? {
        switch self {
        case .stopService(let target, _), .renewLease(let target, _), .restartService(let target):
            return target
        case .observe, .reclaim, .handOff:
            return nil
        }
    }
}

// MARK: - Approval

/// Who has to say yes before a step runs.
public enum RunbookApproval: String, Codable, Sendable, CaseIterable {
    /// Runs on its own. Only ever legal for a read-only step.
    case automatic
    /// The operator sees the exact action and approves this one instance.
    case operatorApproval
}

// MARK: - Stopping

/// A condition that ends the run and hands the situation back to a human.
///
/// Authored per runbook rather than assumed, because writing them down is the
/// part that makes the author think about what they are automating. Validation
/// enforces the one that is not optional — see `RunbookValidation`.
public enum RunbookStop: String, Codable, Sendable, CaseIterable {
    /// The culprit is a process the controller does not own. Nothing in this
    /// product signals a process it did not start.
    case targetUnmanaged
    /// More candidates matched than the runbook is willing to act on.
    case tooManyTargets
    /// Required evidence could not be gathered, so the diagnosis is a guess.
    case evidenceUnavailable
    /// The operator declined a step.
    case approvalDenied
    /// A step reported failure. Later steps assumed it worked.
    case stepFailed
    /// Every step ran and the symptom is still there.
    case exhausted

    /// One line for the operator, not for the log.
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

// MARK: - Steps

public struct RunbookStep: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    /// What the operator reads in the approval list.
    public var title: String
    public var action: RunbookAction
    /// Why the author put this step here. Required, and shown next to the
    /// action: an approval prompt the operator cannot reason about is a prompt
    /// they will learn to click through.
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

// MARK: - The document

public struct Runbook: Codable, Sendable, Hashable, Identifiable {
    /// The schema this document is written against. A reader that does not know
    /// the version refuses the document rather than guessing at it.
    public static let currentFormat = 1

    public var id: String
    public var formatVersion: Int
    /// This document's own version, bumped by its author. Distinct from
    /// `formatVersion`: the schema and the content change for different reasons
    /// and by different hands.
    public var revision: Int
    public var title: String
    /// The situation in the operator's words — what they would say out loud,
    /// which is also what a model matches against.
    public var symptom: String
    /// What the model is told before it sees any evidence. The author's voice:
    /// the domain knowledge that makes a general model useful about this one
    /// situation, and the reason a runbook is worth shipping at all.
    public var briefing: String
    public var parameters: [RunbookParameter]
    /// Gathered up front, before any step runs.
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

    /// The steps that change nothing, in order. This is the whole of what the
    /// read-only diagnosis pass may run, and it is derived rather than declared
    /// so the two can never disagree.
    public var diagnosis: [RunbookStep] { steps.filter(\.isReadOnly) }

    /// The steps that need a human. What the approval sheet lists.
    public var mutations: [RunbookStep] { steps.filter { !$0.isReadOnly } }

    /// Whether anything in here can change the machine at all. A runbook that
    /// cannot is safe to run unattended and is worth saying so about.
    public var isAdvisoryOnly: Bool { mutations.isEmpty }

    public func parameter(named name: String) -> RunbookParameter? {
        parameters.first { $0.name == name }
    }
}
