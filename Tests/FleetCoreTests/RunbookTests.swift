import XCTest
@testable import FleetCore

final class RunbookTests: XCTestCase {

    private func valid(
        parameters: [RunbookParameter] = [],
        evidence: [RunbookEvidence] = [.managedServices],
        steps: [RunbookStep]? = nil,
        stopWhen: Set<RunbookStop> = [],
        formatVersion: Int = Runbook.currentFormat,
        revision: Int = 1
    ) -> Runbook {
        Runbook(
            id: "test", formatVersion: formatVersion, revision: revision,
            title: "Test", symptom: "Something is wrong.", briefing: "Look at the thing.",
            parameters: parameters, evidence: evidence,
            steps: steps ?? [look], stopWhen: stopWhen)
    }

    private let look = RunbookStep(
        id: "look", title: "Look", action: .observe(.managedServices),
        rationale: "Because you have to look first.", approval: .automatic)

    private func stop(_ target: RunbookTarget,
                      approval: RunbookApproval = .operatorApproval,
                      rationale: String = "Because it is orphaned.") -> RunbookStep {
        RunbookStep(id: "stop", title: "Stop it",
                    action: .stopService(target, reason: "orphaned"),
                    rationale: rationale, approval: approval)
    }

    private func criticals(_ runbook: Runbook) -> [String] {
        runbook.defects.filter { $0.severity == .critical }.map(\.message)
    }

    private func warnings(_ runbook: Runbook) -> [String] {
        runbook.defects.filter { $0.severity == .warning }.map(\.message)
    }

    func testEveryShippedRunbookIsClean() {
        for runbook in RunbookLibrary.all {
            XCTAssertTrue(runbook.defects.isEmpty,
                          "\(runbook.id): \(runbook.defects.map(\.message))")
        }
    }

    func testShippedRunbookIDsAreUniqueAndResolvable() {
        let ids = RunbookLibrary.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for id in ids {
            XCTAssertEqual(RunbookLibrary.runbook(id: id)?.id, id)
        }
        XCTAssertNil(RunbookLibrary.runbook(id: "no-such-runbook"))
    }

    func testDiagnosisAndMutationsPartitionEveryRunbook() {
        for runbook in RunbookLibrary.all {
            let split = runbook.diagnosis.count + runbook.mutations.count
            XCTAssertEqual(split, runbook.steps.count, runbook.id)
            XCTAssertTrue(runbook.diagnosis.allSatisfy(\.isReadOnly), runbook.id)
            XCTAssertTrue(runbook.mutations.allSatisfy { !$0.isReadOnly }, runbook.id)
        }
    }

    func testNoShippedRunbookChangesAnythingUnattended() {
        for runbook in RunbookLibrary.all {
            for step in runbook.mutations {
                XCTAssertEqual(step.approval, .operatorApproval, "\(runbook.id)/\(step.id)")
            }
        }
    }

    func testShippedRunbooksSurviveADocumentRoundTrip() throws {
        for runbook in RunbookLibrary.all {
            let data = try JSONEncoder().encode(runbook)
            let decoded = try JSONDecoder().decode(Runbook.self, from: data)
            XCTAssertEqual(decoded, runbook, runbook.id)
        }
    }

    func testReclaimScopeHasNoSecondRung() {
        XCTAssertEqual(RunbookReclaimScope.allCases, [.regeneratesFreely])
    }

    func testAnUnattendedMutationIsRefused() {
        let runbook = valid(steps: [stop(.parameter("svc"), approval: .automatic)],
                            stopWhen: [.targetUnmanaged])
        XCTAssertFalse(runbook.isLoadable)
        XCTAssertTrue(criticals(runbook).contains { $0.contains("without asking") })
    }

    func testAnApprovedMutationIsAccepted() {
        let runbook = valid(parameters: [RunbookParameter(name: "svc", kind: .serviceID,
                                                          prompt: "Which service?")],
                            steps: [stop(.parameter("svc"))],
                            stopWhen: [.targetUnmanaged])
        XCTAssertTrue(runbook.isLoadable, "\(runbook.defects.map(\.message))")
    }

    func testApprovalOnAReadOnlyStepIsWarnedAbout() {
        let observe = RunbookStep(id: "look", title: "Look",
                                  action: .observe(.managedServices),
                                  rationale: "Have to look.", approval: .operatorApproval)
        let runbook = valid(steps: [observe])
        XCTAssertTrue(runbook.isLoadable)
        XCTAssertTrue(warnings(runbook).contains { $0.contains("approval to change nothing") })
    }

    func testAMutationWithoutARationaleIsRefused() {
        let runbook = valid(parameters: [RunbookParameter(name: "svc", kind: .serviceID,
                                                          prompt: "Which?")],
                            steps: [stop(.parameter("svc"), rationale: "  ")],
                            stopWhen: [.targetUnmanaged])
        XCTAssertFalse(runbook.isLoadable)
        XCTAssertTrue(criticals(runbook).contains { $0.contains("no rationale") })
    }

    func testAReadOnlyStepWithoutARationaleIsOnlyAWarning() {
        let observe = RunbookStep(id: "look", title: "Look",
                                  action: .observe(.managedServices),
                                  rationale: "", approval: .automatic)
        let runbook = valid(steps: [observe])
        XCTAssertTrue(runbook.isLoadable)
        XCTAssertTrue(warnings(runbook).contains { $0.contains("no rationale") })
    }

    func testASweepAtTheCeilingIsAccepted() {
        let runbook = valid(steps: [stop(.each(.leaseExpired, max: RunbookValidation.maxTargets))],
                            stopWhen: [.targetUnmanaged, .tooManyTargets])
        XCTAssertTrue(runbook.isLoadable, "\(runbook.defects.map(\.message))")
    }

    func testASweepAboveTheCeilingIsRefused() {
        let over = RunbookValidation.maxTargets + 1
        let runbook = valid(steps: [stop(.each(.leaseExpired, max: over))],
                            stopWhen: [.targetUnmanaged, .tooManyTargets])
        XCTAssertFalse(runbook.isLoadable)
        XCTAssertTrue(criticals(runbook).contains { $0.contains("ceiling") })
    }

    func testACapOfZeroIsRefused() {
        let runbook = valid(steps: [stop(.each(.leaseExpired, max: 0))],
                            stopWhen: [.targetUnmanaged, .tooManyTargets])
        XCTAssertFalse(runbook.isLoadable)
        XCTAssertTrue(criticals(runbook).contains { $0.contains("matches nothing") })
    }

    func testASweepWithoutATooManyStopIsWarnedAbout() {
        let runbook = valid(steps: [stop(.each(.leaseExpired, max: 3))],
                            stopWhen: [.targetUnmanaged])
        XCTAssertTrue(runbook.isLoadable)
        XCTAssertTrue(warnings(runbook).contains { $0.contains("more than it expected") })
    }

    func testAStepReferringToAnUndeclaredParameterIsRefused() {
        let runbook = valid(steps: [stop(.parameter("nope"))], stopWhen: [.targetUnmanaged])
        XCTAssertFalse(runbook.isLoadable)
        XCTAssertTrue(criticals(runbook).contains { $0.contains("undeclared parameter 'nope'") })
    }

    func testEvidenceReferringToAnUndeclaredParameterIsRefused() {
        let runbook = valid(evidence: [.listenersOnPort(parameter: "port")])
        XCTAssertFalse(runbook.isLoadable)
        XCTAssertTrue(criticals(runbook).contains { $0.contains("undeclared parameter 'port'") })
    }

    func testAQueryReferringToAnUndeclaredParameterIsRefused() {
        let runbook = valid(steps: [stop(.each(.ownedBy(parameter: "who"), max: 2))],
                            stopWhen: [.targetUnmanaged, .tooManyTargets])
        XCTAssertFalse(runbook.isLoadable)
        XCTAssertTrue(criticals(runbook).contains { $0.contains("undeclared parameter 'who'") })
    }

    func testAnUnusedParameterIsWarnedAbout() {
        let runbook = valid(parameters: [RunbookParameter(name: "spare", kind: .path,
                                                          prompt: "Which path?")])
        XCTAssertTrue(runbook.isLoadable)
        XCTAssertTrue(warnings(runbook).contains { $0.contains("'spare' is asked for and never used") })
    }

    func testActingOnServicesWithoutAnUnmanagedStopIsRefused() {
        let runbook = valid(parameters: [RunbookParameter(name: "svc", kind: .serviceID,
                                                          prompt: "Which?")],
                            steps: [stop(.parameter("svc"))],
                            stopWhen: [])
        XCTAssertFalse(runbook.isLoadable)
        XCTAssertTrue(criticals(runbook).contains { $0.contains("not the controller's to touch") })
    }

    func testAStorageOnlyRunbookNeedsNoUnmanagedStop() {
        let reclaim = RunbookStep(id: "clear", title: "Clear caches",
                                  action: .reclaim(.regeneratesFreely),
                                  rationale: "They come back.", approval: .operatorApproval)
        let runbook = valid(evidence: [.reclaimCandidates], steps: [reclaim], stopWhen: [])
        XCTAssertTrue(runbook.isLoadable, "\(runbook.defects.map(\.message))")
        XCTAssertTrue(runbook.defects.isEmpty, "\(runbook.defects.map(\.message))")
    }

    func testAReadOnlyRunbookNeedsNoUnmanagedStop() {
        XCTAssertTrue(valid().defects.isEmpty)
        XCTAssertTrue(valid().isAdvisoryOnly)
    }

    func testAnUnknownFormatVersionIsRefused() {
        let runbook = valid(formatVersion: Runbook.currentFormat + 1)
        XCTAssertFalse(runbook.isLoadable)
        XCTAssertTrue(criticals(runbook).contains { $0.contains("format version") })
    }

    func testARunbookWithNoStepsIsRefused() {
        let runbook = valid(steps: [])
        XCTAssertFalse(runbook.isLoadable)
        XCTAssertTrue(criticals(runbook).contains { $0.contains("no steps") })
    }

    func testDuplicateStepIDsAreRefused() {
        let runbook = valid(steps: [look, look])
        XCTAssertFalse(runbook.isLoadable)
        XCTAssertTrue(criticals(runbook).contains { $0.contains("duplicate step id") })
    }

    func testAStopWithNoReasonIsWarnedAbout() {
        let silent = RunbookStep(id: "stop", title: "Stop it",
                                 action: .stopService(.parameter("svc"), reason: ""),
                                 rationale: "It is orphaned.", approval: .operatorApproval)
        let runbook = valid(parameters: [RunbookParameter(name: "svc", kind: .serviceID,
                                                          prompt: "Which?")],
                            steps: [silent], stopWhen: [.targetUnmanaged])
        XCTAssertTrue(runbook.isLoadable)
        XCTAssertTrue(warnings(runbook).contains { $0.contains("event log will not explain itself") })
    }

    func testDefectsAreOrderedMostSevereFirst() {
        let runbook = valid(parameters: [RunbookParameter(name: "spare", kind: .path,
                                                          prompt: "Which path?")],
                            steps: [stop(.each(.leaseExpired, max: 2), approval: .automatic)],
                            stopWhen: [.targetUnmanaged, .tooManyTargets])
        XCTAssertEqual(runbook.defects.first?.severity, .critical)
        XCTAssertEqual(runbook.defects.last?.severity, .warning)
    }

    func testOnlyCriticalsBlockLoading() {
        let warned = valid(parameters: [RunbookParameter(name: "spare", kind: .path,
                                                         prompt: "Which?")])
        XCTAssertFalse(warned.defects.isEmpty)
        XCTAssertTrue(warned.isLoadable)
    }
}
