import Foundation

public struct RunbookDefect: Sendable, Hashable, Identifiable {
    public enum Severity: String, Sendable, Hashable {
        case critical
        case warning
    }

    public var severity: Severity
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

    public static let maxTargets = 10

    public static func defects(in runbook: Runbook) -> [RunbookDefect] {
        var defects: [RunbookDefect] = []
        defects += documentDefects(runbook)
        defects += stepDefects(runbook)
        defects += parameterDefects(runbook)
        defects += stopDefects(runbook)
        return defects
    }

    private static func documentDefects(_ runbook: Runbook) -> [RunbookDefect] {
        var defects: [RunbookDefect] = []

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

    private static func stepDefects(_ runbook: Runbook) -> [RunbookDefect] {
        var defects: [RunbookDefect] = []
        for step in runbook.steps {
            if !step.isReadOnly, step.approval == .automatic {
                defects.append(.init(
                    severity: .critical, stepID: step.id,
                    message: "changes the machine without asking — every mutation needs approval"))
            }
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

    private static func stopDefects(_ runbook: Runbook) -> [RunbookDefect] {
        var defects: [RunbookDefect] = []
        let touchesServices = runbook.steps.contains { !$0.isReadOnly && $0.action.target != nil }

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
    var defects: [RunbookDefect] {
        RunbookValidation.defects(in: self).sorted {
            ($0.severity == .critical ? 0 : 1, $0.stepID ?? "", $0.message)
                < ($1.severity == .critical ? 0 : 1, $1.stepID ?? "", $1.message)
        }
    }

    var isLoadable: Bool {
        !defects.contains { $0.severity == .critical }
    }
}
