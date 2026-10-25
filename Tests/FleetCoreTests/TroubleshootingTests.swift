import XCTest
@testable import FleetCore

/// Suggestions are the product surface that tells a person what is going on
/// without doing it for them. The failure modes that matter are inventing a
/// problem from missing evidence, ranking on lifetime/global figures instead
/// of the event slice, collapsing two categories that should both show, and
/// offering a signal on something the controller does not own.
final class TroubleshootingTests: XCTestCase {

    /// Fixed instant so recency, staleness and lease remaining do not depend
    /// on when the suite runs.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    private func service(
        id: String = "svc-a",
        name: String = "api",
        state: ServiceState = .unhealthy,
        claimed: Bool = false,
        declaredPorts: [Int] = [],
        evidence: Evidence = Evidence(),
        leaseOffset: TimeInterval = 3_600,
        consecutiveHealthFailures: Int = 0,
        lastExitCode: Int32? = nil
    ) -> ServiceRecord {
        var record = ServiceRecord(
            id: id, friendlyName: name, ownerAgent: "codex",
            purpose: "fixture", command: ["fixture"], cwd: "/tmp",
            declaredPorts: declaredPorts,
            startedAt: now.addingTimeInterval(-3_600),
            leaseExpiresAt: now.addingTimeInterval(leaseOffset),
            leaseTTLSec: 3_600,
            state: state,
            evidence: evidence,
            consecutiveHealthFailures: consecutiveHealthFailures,
            lastExitCode: lastExitCode,
            updatedAt: now)
        record.claimed = claimed
        return record
    }

    private func item(id: String, title: String, detail: String = "detail",
                      serviceID: String? = nil, unmanagedID: String? = nil) -> AttentionItem {
        AttentionItem(id: id, severity: .critical, title: title, detail: detail,
                      serviceID: serviceID, unmanagedID: unmanagedID, since: now)
    }

    private func event(seq: Int64, kind: EventKind, serviceID: String?,
                       age: TimeInterval = 60, detail: String = "event") -> ServiceEvent {
        ServiceEvent(seq: seq, serviceID: serviceID, serviceName: serviceID,
                     ts: now.addingTimeInterval(-age), kind: kind, detail: detail)
    }

    private func freshHealthFailed(detail: String = "connection refused") -> Evidence {
        Evidence(processExists: true, listeningPorts: [8787], portScanRan: true,
                 healthCheckRan: true, healthPassed: false, healthDetail: detail,
                 checkedAt: now.addingTimeInterval(-5))
    }

    private func suggest(items: [AttentionItem] = [],
                         services: [ServiceRecord] = [],
                         events: [ServiceEvent] = []) -> [TroubleshootingSuggestion] {
        Troubleshooting.suggestions(items: items, services: services, events: events, now: now)
    }

    // MARK: - Ranking

    func testRecurrenceRanksByBoundedRecentEventCount() {
        let a = service(id: "svc-a", name: "alpha", evidence: freshHealthFailed())
        let b = service(id: "svc-b", name: "beta", evidence: freshHealthFailed())
        var events: [ServiceEvent] = []
        for i in 1...5 {
            events.append(event(seq: Int64(i), kind: .healthFailed, serviceID: "svc-a", age: TimeInterval(i * 10)))
        }
        events.append(event(seq: 10, kind: .healthFailed, serviceID: "svc-b", age: 10))
        events.append(event(seq: 11, kind: .healthFailed, serviceID: "svc-b", age: 20))
        let result = suggest(
            items: [
                item(id: "unhealthy-svc-a", title: "alpha: health check failing", serviceID: "svc-a"),
                item(id: "unhealthy-svc-b", title: "beta: health check failing", serviceID: "svc-b"),
            ],
            services: [b, a],
            events: events)
        XCTAssertEqual(result.map(\.id), ["health-svc-a", "health-svc-b"])
        XCTAssertEqual(result[0].occurrences, 5)
        XCTAssertEqual(result[1].occurrences, 2)
        XCTAssertTrue(result[0].evidence.contains("5 matching events"))
        XCTAssertTrue(result[1].evidence.contains("2 matching events"))
    }

    func testEventsOutsideTheRecencyWindowDoNotCount() {
        let record = service(evidence: freshHealthFailed())
        let recent = event(seq: 2, kind: .healthFailed, serviceID: "svc-a", age: 60)
        let stale = event(seq: 1, kind: .healthFailed, serviceID: "svc-a",
                          age: Troubleshooting.recencyWindow + 120)
        let result = suggest(
            items: [item(id: "unhealthy-svc-a", title: "api failing", serviceID: "svc-a")],
            services: [record],
            events: [stale, recent])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].occurrences, 1)
        XCTAssertFalse(result[0].evidence.contains("2 matching"))
    }

    func testCrashRecurrenceRanksAboveASingleCurrentFailureWithFewerEvents() {
        let looping = service(id: "svc-loop", name: "loop", state: .running,
                              evidence: Evidence(processExists: true, portScanRan: true,
                                                 checkedAt: now.addingTimeInterval(-5)))
        let sick = service(id: "svc-sick", name: "sick", state: .unhealthy, evidence: freshHealthFailed())
        var crashEvents: [ServiceEvent] = []
        for i in 1...4 {
            crashEvents.append(event(seq: Int64(i), kind: .crashed,
                                     serviceID: "svc-loop", age: TimeInterval(i * 30)))
        }
        let result = suggest(
            services: [sick, looping],
            events: crashEvents + [event(seq: 50, kind: .healthFailed, serviceID: "svc-sick", age: 15)])
        XCTAssertEqual(result.first?.id, "crash-svc-loop")
        XCTAssertEqual(result.first?.occurrences, 4)
        XCTAssertEqual(result.map(\.id).sorted(), ["crash-svc-loop", "health-svc-sick"].sorted())
    }

    func testEqualRecurrenceSortsByStableId() {
        let a = service(id: "svc-z", name: "z", evidence: freshHealthFailed())
        let b = service(id: "svc-m", name: "m", evidence: freshHealthFailed())
        let events = [
            event(seq: 1, kind: .healthFailed, serviceID: "svc-z"),
            event(seq: 2, kind: .healthFailed, serviceID: "svc-m"),
        ]
        let result = suggest(services: [a, b], events: events)
        XCTAssertEqual(result.map(\.id), ["health-svc-m", "health-svc-z"])
    }

    func testInputOrderDoesNotChangeResult() {
        let a = service(id: "svc-a", evidence: freshHealthFailed())
        let b = service(id: "svc-b", evidence: freshHealthFailed())
        let items = [
            item(id: "unhealthy-svc-a", title: "a", serviceID: "svc-a"),
            item(id: "unhealthy-svc-b", title: "b", serviceID: "svc-b"),
        ]
        let events = [
            event(seq: 1, kind: .healthFailed, serviceID: "svc-a", age: 10),
            event(seq: 2, kind: .healthFailed, serviceID: "svc-a", age: 20),
            event(seq: 3, kind: .healthFailed, serviceID: "svc-b", age: 10),
        ]
        let forward = suggest(items: items, services: [a, b], events: events)
        let reversed = suggest(items: items.reversed(), services: [b, a], events: events.reversed())
        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward.map(\.id), reversed.map(\.id))
    }

    // MARK: - Unavailable / stale evidence

    func testMissingPortScanDoesNotInventMissingListeners() {
        let record = service(
            state: .running,
            declaredPorts: [8787],
            evidence: Evidence(processExists: true, listeningPorts: [], portScanRan: false,
                               checkedAt: now.addingTimeInterval(-5)))
        XCTAssertTrue(suggest(services: [record]).isEmpty)
    }

    func testStalePortScanDoesNotClaimMissingListeners() {
        let record = service(
            state: .running,
            declaredPorts: [8787],
            evidence: Evidence(processExists: true, listeningPorts: [], portScanRan: true,
                               checkedAt: now.addingTimeInterval(-3_600)))
        XCTAssertTrue(suggest(services: [record]).isEmpty)
    }

    func testProcessGoneDoesNotInventAMissingListener() {
        let record = service(
            state: .running,
            declaredPorts: [8787],
            evidence: Evidence(processExists: false, listeningPorts: [], portScanRan: true,
                               checkedAt: now.addingTimeInterval(-5)))
        XCTAssertFalse(suggest(services: [record]).contains { $0.id.hasPrefix("listener-") })
    }

    func testFreshScanWithMissingDeclaredPortSurfacesAListenerSuggestion() {
        let record = service(
            state: .running,
            declaredPorts: [8787, 8788],
            evidence: Evidence(processExists: true, listeningPorts: [8787], portScanRan: true,
                               checkedAt: now.addingTimeInterval(-5)))
        let result = suggest(services: [record])
        XCTAssertEqual(result.map(\.id), ["listener-svc-a"])
        XCTAssertTrue(result[0].evidence.contains("missing :8788"))
        XCTAssertTrue(result[0].checks.contains { $0.contains("unavailable") })
    }

    func testStaleHealthEvidenceIsDescribedAsStaleNotAFreshFailure() {
        var evidence = freshHealthFailed()
        evidence.checkedAt = now.addingTimeInterval(-3_600)
        let record = service(state: .unhealthy, evidence: evidence)
        let result = suggest(
            items: [item(id: "unhealthy-svc-a", title: "api: health check failing", serviceID: "svc-a")],
            services: [record])
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].evidence.contains("stale"))
        XCTAssertFalse(result[0].evidence.contains("Recorded health check failed"))
    }

    func testUnavailableProcessExistenceIsStatedAsUnavailable() {
        let evidence = Evidence(processExists: nil, portScanRan: false, healthCheckRan: true,
                                healthPassed: false, healthDetail: "timeout",
                                checkedAt: now.addingTimeInterval(-5))
        let record = service(state: .unhealthy, evidence: evidence)
        let result = suggest(services: [record])
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].evidence.contains("Process existence is unavailable"))
        XCTAssertTrue(result[0].evidence.contains("process presence is not a health result"))
    }

    // MARK: - No invention

    func testEmptyInputsProduceNothing() {
        XCTAssertTrue(suggest().isEmpty)
    }

    func testHealthyVerifiedServicesProduceNothing() {
        let record = service(
            state: .healthy,
            declaredPorts: [8787],
            evidence: Evidence(processExists: true, listeningPorts: [8787], portScanRan: true,
                               healthCheckRan: true, healthPassed: true, checkedAt: now.addingTimeInterval(-5)))
        XCTAssertTrue(suggest(services: [record], events: [
            event(seq: 1, kind: .healthPassed, serviceID: "svc-a"),
            event(seq: 2, kind: .started, serviceID: "svc-a"),
        ]).isEmpty)
    }

    func testUnknownAttentionIDsAreIgnored() {
        let record = service(state: .healthy, evidence: Evidence(processExists: true, checkedAt: now))
        let result = suggest(
            items: [
                item(id: "mystery-svc-a", title: "invented", serviceID: "svc-a"),
                item(id: "degraded-svc-a", title: "budget", serviceID: "svc-a"),
                item(id: "stale-svc-a", title: "stale", serviceID: "svc-a"),
                item(id: "device-other", title: "unreachable"),
            ],
            services: [record])
        XCTAssertTrue(result.isEmpty)
    }

    func testProcessExistenceIsNotTreatedAsHealth() {
        let record = service(
            state: .running,
            evidence: Evidence(processExists: true, portScanRan: false, healthCheckRan: false,
                               checkedAt: now.addingTimeInterval(-5)))
        let result = suggest(services: [record])
        XCTAssertTrue(result.isEmpty, "a live process with no health check is Running (unverified), not a failure")
    }

    func testRecoveredHealthDoesNotSurfaceFromOldFailuresAlone() {
        let record = service(
            state: .healthy,
            evidence: Evidence(processExists: true, portScanRan: true, healthCheckRan: true,
                               healthPassed: true, checkedAt: now.addingTimeInterval(-5)))
        var events: [ServiceEvent] = []
        for i in 1...6 {
            events.append(event(seq: Int64(i), kind: .healthFailed, serviceID: "svc-a", age: TimeInterval(i * 20)))
        }
        XCTAssertTrue(suggest(services: [record], events: events).isEmpty)
    }

    func testOverlappingDeclaredPortsAreNotAConflictWithoutEvents() {
        let a = service(id: "svc-a", state: .running, declaredPorts: [8787],
                        evidence: Evidence(processExists: true, listeningPorts: [8787],
                                           portScanRan: true, checkedAt: now.addingTimeInterval(-5)))
        let b = service(id: "svc-b", name: "other", state: .running, declaredPorts: [8787],
                        evidence: Evidence(processExists: true, listeningPorts: [],
                                           portScanRan: false, checkedAt: now.addingTimeInterval(-5)))
        let result = suggest(services: [a, b])
        XCTAssertFalse(result.contains { $0.id.hasPrefix("port-") })
    }

    func testPortConflictRequiresAPortViolationEvent() {
        let record = service(state: .running, declaredPorts: [8787],
                             evidence: Evidence(processExists: true, listeningPorts: [8787, 9999],
                                                portScanRan: true, checkedAt: now.addingTimeInterval(-5)))
        XCTAssertTrue(suggest(services: [record]).filter { $0.id.hasPrefix("port-") }.isEmpty)
        let result = suggest(services: [record], events: [
            event(seq: 1, kind: .portViolation, serviceID: "svc-a", detail: "listening on :9999"),
        ])
        XCTAssertEqual(result.map(\.id), ["port-svc-a"])
        XCTAssertEqual(result[0].occurrences, 1)
        XCTAssertTrue(result[0].evidence.contains("portViolation"))
    }

    func testSingleCrashEventWhileRunningIsNotALoop() {
        let record = service(state: .running,
                             evidence: Evidence(processExists: true, checkedAt: now.addingTimeInterval(-5)))
        XCTAssertTrue(suggest(services: [record], events: [
            event(seq: 1, kind: .crashed, serviceID: "svc-a"),
        ]).isEmpty)
    }

    func testEvidenceDoesNotInventStatisticalOrGlobalClaims() {
        let record = service(evidence: freshHealthFailed(), consecutiveHealthFailures: 3)
        var events: [ServiceEvent] = []
        for i in 1...3 {
            events.append(event(seq: Int64(i), kind: .healthFailed, serviceID: "svc-a", age: TimeInterval(i * 10)))
        }
        let text = suggest(services: [record], events: events)[0].evidence.lowercased()
        for banned in ["%", "percent", "fleet-wide", "always", "never fails", "on average", "mtbf"] {
            XCTAssertFalse(text.contains(banned), "invented claim: \(banned)")
        }
        XCTAssertTrue(text.contains("bounded recent log"))
    }

    // MARK: - Bounded inputs

    func testSuggestionCountIsCappedAndKeepsHighestRecurrence() {
        var services: [ServiceRecord] = []
        var events: [ServiceEvent] = []
        var seq: Int64 = 1
        for i in 0..<12 {
            let id = String(format: "svc-%02d", i)
            services.append(service(id: id, name: id, evidence: freshHealthFailed()))
            let copies = i < 2 ? 5 : 1
            for _ in 0..<copies {
                events.append(event(seq: seq, kind: .healthFailed, serviceID: id, age: TimeInterval(seq)))
                seq += 1
            }
        }
        let result = suggest(services: services, events: events)
        XCTAssertEqual(result.count, Troubleshooting.maxSuggestions)
        XCTAssertEqual(Set(result.map(\.id)).count, result.count)
        XCTAssertEqual(result[0].occurrences, 5)
        XCTAssertEqual(result[1].occurrences, 5)
        XCTAssertTrue(result[0].occurrences >= result.last!.occurrences)
        XCTAssertEqual(result.map(\.id).sorted(), result.map(\.id).sorted())
        let high = Set(result.prefix(2).map(\.id))
        XCTAssertEqual(high, ["health-svc-00", "health-svc-01"])
    }

    func testEventConsumptionIsCapped() {
        let record = service(evidence: freshHealthFailed())
        var events: [ServiceEvent] = []
        for i in 1...Troubleshooting.maxEvents + 50 {
            events.append(event(seq: Int64(i), kind: .healthFailed, serviceID: "svc-a",
                                age: TimeInterval(i)))
        }
        let result = suggest(services: [record], events: events)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].occurrences, Troubleshooting.maxEvents)
        XCTAssertTrue(result[0].evidence.contains("\(Troubleshooting.maxEvents) matching events"))
    }

    func testCheckAndRemedyListsAreCapped() {
        let record = service(evidence: freshHealthFailed())
        let result = suggest(services: [record])
        XCTAssertEqual(result.count, 1)
        XCTAssertLessThanOrEqual(result[0].checks.count, Troubleshooting.maxChecks)
        XCTAssertLessThanOrEqual(result[0].remedies.count, Troubleshooting.maxRemedies)
        XCTAssertFalse(result[0].checks.isEmpty)
        XCTAssertFalse(result[0].remedies.isEmpty)
        for line in result[0].checks + result[0].remedies {
            XCTAssertLessThanOrEqual(line.count, Troubleshooting.maxLineChars)
        }
    }

    func testEvidenceStringIsCapped() {
        let detail = String(repeating: "x", count: 4_000)
        let result = suggest(
            items: [item(id: "unhealthy-svc-a", title: "failing", detail: detail, serviceID: "svc-a")],
            services: [service(evidence: freshHealthFailed())])
        XCTAssertEqual(result.count, 1)
        XCTAssertLessThanOrEqual(result[0].evidence.count, Troubleshooting.maxEvidenceChars)
        XCTAssertTrue(result[0].evidence.contains("…"))
    }

    // MARK: - Dedup

    func testHealthAttentionStateAndEventsCollapseToOneSuggestion() {
        let record = service(evidence: freshHealthFailed(), consecutiveHealthFailures: 4)
        let result = suggest(
            items: [
                item(id: "unhealthy-svc-a", title: "api: health check failing", serviceID: "svc-a"),
                item(id: "unhealthy-svc-a", title: "duplicate", serviceID: "svc-a"),
            ],
            services: [record],
            events: [
                event(seq: 1, kind: .healthFailed, serviceID: "svc-a", age: 10),
                event(seq: 2, kind: .healthFailed, serviceID: "svc-a", age: 20),
            ])
        XCTAssertEqual(result.map(\.id), ["health-svc-a"])
        XCTAssertEqual(result[0].occurrences, 2)
    }

    func testDifferentCategoriesForOneServiceBothSurface() {
        let record = service(
            state: .unhealthy,
            declaredPorts: [8787],
            evidence: Evidence(processExists: true, listeningPorts: [], portScanRan: true,
                               healthCheckRan: true, healthPassed: false, healthDetail: "refused",
                               checkedAt: now.addingTimeInterval(-5)))
        let result = suggest(services: [record])
        XCTAssertEqual(Set(result.map(\.id)), ["health-svc-a", "listener-svc-a"])
    }

    func testDaemonCrashLoopDedupsAttentionAndEvents() {
        let events = [
            event(seq: 1, kind: .daemonCrashed, serviceID: nil, age: 100, detail: "abnormal exit"),
            event(seq: 2, kind: .daemonCrashed, serviceID: nil, age: 50, detail: "abnormal exit"),
        ]
        let result = suggest(
            items: [item(id: "daemon-crashloop", title: "The controller has been restarting")],
            events: events)
        XCTAssertEqual(result.map(\.id), ["crash-daemon"])
        XCTAssertEqual(result[0].occurrences, 2)
        XCTAssertTrue(result[0].title.contains("controller"))
    }

    func testSuggestionIdsAreStableAcrossCalls() {
        let record = service(evidence: freshHealthFailed())
        let items = [item(id: "unhealthy-svc-a", title: "failing", serviceID: "svc-a")]
        let a = suggest(items: items, services: [record])
        let b = suggest(items: items, services: [record])
        XCTAssertEqual(a.map(\.id), ["health-svc-a"])
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set(a).count, a.count)
    }

    // MARK: - Safety: no action, no unmanaged signal, no false health

    func testClaimedLeaseRemediesDoNotPromiseAReap() {
        var record = service(state: .expired, claimed: true, leaseOffset: -60)
        record.claimed = true
        let result = suggest(
            items: [item(id: "expired-svc-a", title: "api: lease expired",
                         detail: "Claimed, not launched", serviceID: "svc-a")],
            services: [record])
        XCTAssertEqual(result.map(\.id), ["lease-svc-a"])
        let text = (result[0].remedies + result[0].checks + [result[0].evidence]).joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("claimed"))
        XCTAssertTrue(text.contains("does not reap") || text.contains("will not stop"))
        XCTAssertFalse(text.contains("automatically"))
        for line in result[0].remedies {
            XCTAssertFalse(line.lowercased().contains("controller is reaping"))
        }
    }

    func testLaunchedExpiringLeaseMentionsRenewal() {
        let record = service(state: .expiring, leaseOffset: 90)
        let result = suggest(services: [record])
        XCTAssertEqual(result.map(\.id), ["lease-svc-a"])
        XCTAssertTrue(result[0].remedies.contains { $0.contains("fleetctl renew") })
        XCTAssertTrue(result[0].title.contains("expiring"))
    }

    func testUnmanagedRemediesDoNotAuthorizeSignalling() {
        let result = suggest(items: [
            item(id: "unmanaged-pid:sig", title: "New unmanaged process: node on :3000",
                 detail: "Listening port with no registry record · pid 4421",
                 unmanagedID: "pid:sig"),
        ])
        XCTAssertEqual(result.map(\.id), ["unmanaged-pid:sig"])
        let text = (result[0].checks + result[0].remedies).joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("does not grant") || text.contains("observation-only"))
        for banned in ["sigkill", "sigterm", "kill the", "force kill", "pkill"] {
            XCTAssertFalse(text.contains(banned), "unauthorized signal: \(banned)")
        }
        XCTAssertTrue(result[0].remedies.contains { $0.contains("claim") || $0.contains("Claim") })
    }

    func testClaimedHealthRemediesRefuseControllerSignalling() {
        let record = service(claimed: true, evidence: freshHealthFailed())
        let result = suggest(services: [record])
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].remedies.contains { $0.contains("does not signal claimed") })
        XCTAssertFalse(result[0].remedies.contains { $0.lowercased().contains("restart the service through fleetctl") })
    }

    func testSuggestionsAreProseNotActions() {
        let record = service(evidence: freshHealthFailed())
        let leaked = item(id: "leaked-pid:old", title: "Leaked: python on :8090",
                          detail: "started through the controller but outlived its record",
                          unmanagedID: "pid:old")
        let result = suggest(
            items: [leaked, item(id: "unhealthy-svc-a", title: "api failing", serviceID: "svc-a")],
            services: [record],
            events: [event(seq: 1, kind: .healthFailed, serviceID: "svc-a")])
        XCTAssertFalse(result.isEmpty)
        for suggestion in result {
            for line in suggestion.checks + suggestion.remedies {
                XCTAssertFalse(line.contains("curl "))
                XCTAssertFalse(line.contains("http://"))
                XCTAssertNil(line.range(of: #"\btail\s"#, options: .regularExpression))
                XCTAssertFalse(line.lowercased().contains("will now"))
                XCTAssertFalse(line.lowercased().contains("automatically restart"))
            }
        }
    }

    func testControlledRestartsAndReconciliationDoNotInventACrashLoop() {
        let record = service(state: .running)
        let events = [event(seq: 1, kind: .restarted, serviceID: record.id),
                      event(seq: 2, kind: .restarted, serviceID: record.id),
                      event(seq: 3, kind: .reconcileMissing, serviceID: record.id)]
        XCTAssertTrue(suggest(services: [record], events: events).isEmpty)
    }

    func testUnattributedUnmanagedEventsNeverMergeUnrelatedProcesses() {
        let events = [event(seq: 1, kind: .becameUnmanaged, serviceID: nil, detail: "process A"),
                      event(seq: 2, kind: .becameUnmanaged, serviceID: nil, detail: "process B")]
        XCTAssertTrue(suggest(events: events).isEmpty)
        let result = suggest(items: [item(id: "leaked-process-a", title: "Leaked work", unmanagedID: "process-a")], events: events)
        XCTAssertEqual(result.first?.occurrences, 0)
        XCTAssertTrue(result.first?.checks.first?.contains("outlived its record") == true)
        XCTAssertTrue(result.first?.evidence.contains("cannot be attributed") == true)
        XCTAssertFalse(result.first?.evidence.contains("process B") == true)
    }

    func testLongUntrustedFindingsDoNotEraseStaleEvidenceOrEventScope() {
        var evidence = freshHealthFailed(detail: String(repeating: "hostile detail", count: 300))
        evidence.checkedAt = now.addingTimeInterval(-3600)
        let record = service(evidence: evidence)
        let result = suggest(items: [item(id: "unhealthy-svc-a", title: "failure", detail: String(repeating: "x", count: 5000), serviceID: record.id)],
                             services: [record], events: [event(seq: 1, kind: .healthFailed, serviceID: record.id)])
        XCTAssertTrue(result.first?.evidence.contains("stale") == true)
        XCTAssertTrue(result.first?.evidence.contains("bounded recent log") == true)
    }

    func testMissingOwnershipCannotProduceARestartRemedy() {
        let result = suggest(items: [item(id: "unhealthy-missing", title: "unknown service", serviceID: "missing")])
        XCTAssertEqual(result.first?.occurrences, 0)
        XCTAssertTrue(result.first?.remedies.first?.contains("Missing ownership evidence") == true)
        XCTAssertFalse(result.flatMap(\.remedies).contains { $0.contains("restart the service") })
    }

    func testClaimedPortViolationCannotProduceAControllerStopRemedy() {
        let record = service(state: .running, claimed: true)
        let result = suggest(services: [record], events: [event(seq: 1, kind: .portViolation, serviceID: record.id)])
        XCTAssertEqual(result.first?.id, "port-svc-a")
        XCTAssertTrue(result.first?.remedies.first?.contains("controller cannot stop or restart") == true)
    }

    func testPausedExpiryDoesNotPromiseImmediateReaping() {
        let record = service(state: .paused, leaseOffset: -10)
        let result = suggest(services: [record])
        XCTAssertEqual(result.first?.id, "lease-svc-a")
        XCTAssertTrue(result.first?.evidence.contains("cleanup is deferred") == true)
        XCTAssertTrue(result.first?.remedies.first?.contains("cleanup is deferred") == true)
    }

    func testDuplicateEventsCountOnceAndExtremeExitStatusDoesNotOverflow() {
        let record = service(state: .crashed, lastExitCode: Int32.min)
        let failure = event(seq: 1, kind: .crashed, serviceID: record.id)
        let result = suggest(services: [record], events: [failure, failure])
        XCTAssertEqual(result.first?.occurrences, 1)
        XCTAssertTrue(result.first?.evidence.contains("2147483648") == true)
    }

    func testCrashedStateSurfacesWithoutEvents() {
        let record = service(state: .crashed, lastExitCode: 1)
        let result = suggest(
            items: [item(id: "crashed-svc-a", title: "api crashed", serviceID: "svc-a")],
            services: [record])
        XCTAssertEqual(result.map(\.id), ["crash-svc-a"])
        XCTAssertEqual(result[0].occurrences, 0)
        XCTAssertTrue(result[0].evidence.contains("exit code 1"))
    }
}
