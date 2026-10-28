import Foundation

// The runbook linter.
//
// A runbook arrives as data — eventually from outside this repository, shipped
// beside a model by someone who is not in the room. The type system stops it
// asking for an action that does not exist; this file stops the rest: an
// unattended deletion, a step nobody can justify, a sweep with no ceiling, a
// document that forgot to say what happens when the culprit turns out not to be
// ours.
//
// Every rule here exists because the shape it rejects is one a plausible author
// would otherwise write by accident.

/// One thing wrong with a runbook.
public struct RunbookDefect: Sendable, Hashable, Identifiable {
    public enum Severity: String, Sendable, Hashable {
        /// The document is refused. Loading it would mean running something
        /// whose safety cannot be established by reading it.
        case critical
        /// The document loads. Something about it will make the operator's life
        /// worse, and the author should hear about it.
        case warning
    }

    public var severity: Severity
    /// The step at fault, or `nil` for a defect in the document as a whole.
    public var stepID: String?
    public var message: String

    public var id: String { "\(severity.rawValue):\(stepID ?? "-"):\(message)" }

    public init(severity: Severity, stepID: String? = nil, message: String) {
        self.severity = severity
        self.stepID = stepID
        self.message = message
    }
}

public enum RunbookValidation {

    /// The most services one step may act on.
    ///
    /// Not a performance limit. The approval list is the control, and an
    /// operator asked to approve thirty stops at once will approve them without
    /// reading — at which point the gate has become a formality and the runbook
    /// is unattended in everything but name.
    public static let maxTargets = 10

    public static func defects(in runbook: Runbook) -> [RunbookDefect] {
        var defects: [RunbookDefect] = []
        defects += documentDefects(runbook)
        defects += stepDefects(runbook)
        defects += parameterDefects(runbook)
        defects += stopDefects(runbook)
        return defects
    }

    // MARK: - The document

    private static func documentDefects(_ runbook: Runbook) -> [RunbookDefect] {
        var defects: [RunbookDefect] = []

        // A reader that guesses at an unknown schema is a reader that will one
        // day guess wrong about an action's meaning.
        if runbook.formatVersion != Runbook.currentFormat {
            defects.append(.init(
                severity: .critical,
                message: "format version \(runbook.formatVersion) is not \(Runbook.currentFormat)"))
        }
        if runbook.id.isEmpty {
            defects.append(.init(severity: .critical, message: "the runbook has no id"))
        }
        if runbook.steps.isEmpty {
            defects.append(.init(severity: .critical, message: "the runbook has no steps"))
        }
        if runbook.revision < 1 {
            defects.append(.init(severity: .warning,
                                 message: "revision \(runbook.revision) should start at 1"))
        }
        // The briefing is the domain knowledge the model does not have. Without
        // it the runbook is a list of buttons and the model is guessing.
        if runbook.briefing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defects.append(.init(severity: .warning, message: "the runbook has no briefing"))
        }
        if runbook.symptom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defects.append(.init(severity: .warning,
                                 message: "the runbook does not say what symptom it addresses"))
        }

        var seen = Set<String>()
        for step in runbook.steps where !seen.insert(step.id).inserted {
            defects.append(.init(severity: .critical, stepID: step.id,
                                 message: "duplicate step id"))
        }
        return defects
    }

    // MARK: - Steps

    private static func stepDefects(_ runbook: Runbook) -> [RunbookDefect] {
        var defects: [RunbookDefect] = []
        for step in runbook.steps {
            // The rule the whole format exists to enforce.
            if !step.isReadOnly, step.approval == .automatic {
                defects.append(.init(
                    severity: .critical, stepID: step.id,
                    message: "changes the machine without asking — every mutation needs approval"))
            }
            // The other direction is not dangerous, it is corrosive: approvals
            // for steps that change nothing teach the operator to click through
            // the ones that do.
            if step.isReadOnly, step.approval == .operatorApproval {
                defects.append(.init(
                    severity: .warning, stepID: step.id,
                    message: "asks for approval to change nothing"))
            }

            let rationale = step.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
            if rationale.isEmpty {
                defects.append(.init(
                    severity: step.isReadOnly ? .warning : .critical, stepID: step.id,
                    message: "no rationale — the operator is asked to approve an action "
                        + "nobody explained"))
            }
            if step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                defects.append(.init(severity: .warning, stepID: step.id,
                                     message: "no title for the approval list"))
            }

            defects += targetDefects(step)
            defects += reasonDefects(step)
        }
        return defects
    }

    private static func targetDefects(_ step: RunbookStep) -> [RunbookDefect] {
        guard case .each(_, let max) = step.action.target else { return [] }
        if max < 1 {
            return [.init(severity: .critical, stepID: step.id,
                          message: "a cap of \(max) matches nothing and hides a mistake")]
        }
        if max > maxTargets {
            return [.init(
                severity: .critical, stepID: step.id,
                message: "acts on up to \(max) services at once; the ceiling is \(maxTargets), "
                    + "above which an approval list stops being read")]
        }
        return []
    }

    /// A stop or a hand-off with no reason gives the operator an event they
    /// cannot account for later.
    private static func reasonDefects(_ step: RunbookStep) -> [RunbookDefect] {
        let reason: String?
        switch step.action {
        case .stopService(_, let text), .handOff(let text): reason = text
        default: reason = nil
        }
        guard let reason,
              reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return [] }
        return [.init(severity: .warning, stepID: step.id,
                      message: "no reason recorded, so the event log will not explain itself")]
    }

    // MARK: - Parameters

    private static func parameterDefects(_ runbook: Runbook) -> [RunbookDefect] {
        let declared = Set(runbook.parameters.map(\.name))
        var defects: [RunbookDefect] = []
        var used = Set<String>()

        for evidence in runbook.evidence {
            for name in references(in: evidence) {
                used.insert(name)
                if !declared.contains(name) {
                    defects.append(.init(
                        severity: .critical,
                        message: "evidence refers to undeclared parameter '\(name)'"))
                }
            }
        }

        for step in runbook.steps {
            for name in references(in: step.action) {
                used.insert(name)
                if !declared.contains(name) {
                    defects.append(.init(
                        severity: .critical, stepID: step.id,
                        message: "refers to undeclared parameter '\(name)'"))
                }
            }
        }

        // An input the operator is asked for and nothing consumes is a question
        // with no consequence, which is worse than not asking.
        for name in declared.subtracting(used).sorted() {
            defects.append(.init(severity: .warning,
                                 message: "parameter '\(name)' is asked for and never used"))
        }
        return defects
    }

    private static func references(in evidence: RunbookEvidence) -> [String] {
        switch evidence {
        case .listenersOnPort(let name), .serviceLog(let name, _): return [name]
        case .managedServices, .processTable, .diskUsage, .reclaimCandidates, .recentEvents:
            return []
        }
    }

    private static func references(in action: RunbookAction) -> [String] {
        var names: [String] = []
        if case .observe(let evidence) = action { names += references(in: evidence) }
        switch action.target {
        case .parameter(let name): names.append(name)
        case .each(let query, _): names += references(in: query)
        case nil: break
        }
        return names
    }

    private static func references(in query: RunbookQuery) -> [String] {
        switch query {
        case .ownedBy(let name), .listeningOnPort(let name): return [name]
        case .leaseExpired, .crashLooping: return []
        }
    }

    // MARK: - Stops

    private static func stopDefects(_ runbook: Runbook) -> [RunbookDefect] {
        var defects: [RunbookDefect] = []
        let touchesServices = runbook.steps.contains { !$0.isReadOnly && $0.action.target != nil }

        // The one stop that is not a matter of taste. Nothing in this product
        // signals a process the controller did not start, and a runbook that
        // does not say what it does when the culprit turns out to be somebody
        // else's has not thought about the case that matters most.
        if touchesServices, !runbook.stopWhen.contains(.targetUnmanaged) {
            defects.append(.init(
                severity: .critical,
                message: "acts on services but does not declare what happens when the target "
                    + "is not the controller's to touch"))
        }

        let sweeps = runbook.steps.contains { step in
            if case .each = step.action.target, !step.isReadOnly { return true }
            return false
        }
        if sweeps, !runbook.stopWhen.contains(.tooManyTargets) {
            defects.append(.init(
                severity: .warning,
                message: "acts on a set of services but does not declare a stop for "
                    + "matching more than it expected"))
        }
        return defects
    }
}

public extension Runbook {
    /// Everything wrong with this document, most severe first.
    var defects: [RunbookDefect] {
        RunbookValidation.defects(in: self).sorted {
            ($0.severity == .critical ? 0 : 1, $0.stepID ?? "", $0.message)
                < ($1.severity == .critical ? 0 : 1, $1.stepID ?? "", $1.message)
        }
    }

    /// Whether this document may be run at all. A warning is a note to its
    /// author; a critical is a refusal.
    var isLoadable: Bool {
        !defects.contains { $0.severity == .critical }
    }
}
