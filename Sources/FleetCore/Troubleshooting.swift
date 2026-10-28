import Foundation

// Bounded, evidence-based troubleshooting suggestions.
//
// The console observes; it does not act. This turns attention items, service
// records and a slice of recent events into a short list of common problems a
// person can look at, with checks and remedies as prose. Nothing here reads a
// log, opens a socket, or signals a process.
//
// Recurrence is the count of matching events in the bounded recent slice the
// caller passed — not a lifetime counter, not a fleet-wide rate. Missing
// observations stay unavailable. Process existence is never treated as health.
// Unmanaged and claimed processes are never offered a controller signal.

// MARK: - Suggestion

/// One problem, the evidence it rests on, and what a person may inspect or do.
///
/// `id` is stable for a (category, subject) pair so a UI can diff successive
/// snapshots without inventing its own keys. `occurrences` is the number of
/// matching events in the bounded recent log, or zero when only the current
/// attention/record is present. It is not a failure probability or a lifetime total.
public struct TroubleshootingSuggestion: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var evidence: String
    public var checks: [String]
    public var remedies: [String]
    public var occurrences: Int

    public init(id: String, title: String, evidence: String,
                checks: [String], remedies: [String], occurrences: Int) {
        self.id = id
        self.title = title
        self.evidence = evidence
        self.checks = checks
        self.remedies = remedies
        self.occurrences = occurrences
    }
}

// MARK: - Entry point

public enum Troubleshooting {

    /// Hard caps so a large snapshot cannot grow a wall of advice.
    static let maxSuggestions = 8
    static let maxChecks = 4
    static let maxRemedies = 4
    static let maxEvents = 200
    static let maxEvidenceChars = 480
    static let maxLineChars = 240
    /// Same window the controller uses for a daemon crash loop: two abnormal
    /// exits inside six hours is a pattern; one is not.
    static let recencyWindow: TimeInterval = 6 * 3600
    /// Evidence older than this is stale for listener/health claims. Wider than
    /// the controller's tick×factor (15s) so a snapshot a few seconds old is
    /// still usable, tight enough that an hour-old scan is not "current".
    static let staleTolerance: TimeInterval = 120

    /// Derive suggestions from the current attention list, the service records
    /// those items refer to, and a recent event slice. `now` is injected so the
    /// path is fixture-testable.
    public static func suggestions(items: [AttentionItem],
                                   services: [ServiceRecord],
                                   events: [ServiceEvent],
                                   now: Date = Date()) -> [TroubleshootingSuggestion] {
        let servicesByID = Dictionary(services.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recent = boundEvents(events, now: now)
        var drafts: [Key: Draft] = [:]

        for item in items.sorted(by: { $0.id < $1.id }) {
            guard let key = key(for: item) else { continue }
            var draft = drafts[key] ?? Draft(key: key)
            if draft.attention == nil { draft.attention = item }
            if draft.service == nil, let id = item.serviceID {
                draft.service = servicesByID[id]
            }
            drafts[key] = draft
        }

        for service in services.sorted(by: { $0.id < $1.id }) {
            if let key = key(forStateOf: service, now: now) {
                var draft = drafts[key] ?? Draft(key: key)
                if draft.service == nil { draft.service = service }
                drafts[key] = draft
            }
            if let key = listenerKey(for: service, now: now) {
                var draft = drafts[key] ?? Draft(key: key)
                if draft.service == nil { draft.service = service }
                drafts[key] = draft
            }
        }

        attach(recent, to: &drafts, servicesByID: servicesByID)
        addEventOnlyDrafts(recent, to: &drafts, servicesByID: servicesByID)

        var result: [TroubleshootingSuggestion] = []
        result.reserveCapacity(min(maxSuggestions, drafts.count))
        for draft in drafts.values where isSupported(draft, now: now) {
            result.append(suggestion(from: draft, now: now))
        }
        result.sort {
            if $0.occurrences != $1.occurrences { return $0.occurrences > $1.occurrences }
            return $0.id < $1.id
        }
        if result.count > maxSuggestions {
            result = Array(result.prefix(maxSuggestions))
        }
        return result
    }

    // MARK: Categories

    /// Closed set of problems this function will name. Unknown attention IDs
    /// and unrelated states are ignored rather than turned into a generic
    /// "something is wrong".
    enum Category: String, Sendable, Hashable {
        case health
        case crash
        case lease
        case listener
        case port
        case unmanaged
    }

    struct Key: Hashable, Sendable {
        var category: Category
        var subject: String
        var id: String { "\(category.rawValue)-\(subject)" }
    }

    struct Draft {
        var key: Key
        var attention: AttentionItem? = nil
        var service: ServiceRecord? = nil
        var events: [ServiceEvent] = []
    }

    // MARK: Attention / state → key

    static func key(for item: AttentionItem) -> Key? {
        if item.id == "daemon-crashloop" { return Key(category: .crash, subject: "daemon") }
        let table: [(prefix: String, category: Category, fromService: Bool)] = [
            ("unhealthy-", .health, true),
            ("crashed-", .crash, true),
            ("expired-", .lease, true),
            ("expiring-", .lease, true),
            ("leaked-", .unmanaged, false),
            ("unmanaged-", .unmanaged, false),
        ]
        for entry in table where item.id.hasPrefix(entry.prefix) {
            let stripped = String(item.id.dropFirst(entry.prefix.count))
            let subject: String
            if entry.fromService {
                subject = item.serviceID ?? stripped
            } else {
                subject = item.unmanagedID ?? item.serviceID ?? stripped
            }
            guard !subject.isEmpty else { return nil }
            return Key(category: entry.category, subject: subject)
        }
        return nil
    }

    static func key(forStateOf service: ServiceRecord, now: Date) -> Key? {
        switch service.state {
        case .unhealthy:
            return Key(category: .health, subject: service.id)
        case .crashed:
            return Key(category: .crash, subject: service.id)
        case .expired:
            return Key(category: .lease, subject: service.id)
        case .expiring:
            return Key(category: .lease, subject: service.id)
        default:
            if !service.state.isTerminal, service.leaseExpiresAt <= now {
                return Key(category: .lease, subject: service.id)
            }
            return nil
        }
    }

    /// Missing listeners require a scan that actually ran, on a process that
    /// is not known to be gone, with evidence that is not stale. An empty
    /// `listeningPorts` array without `portScanRan` is "not checked", not
    /// "nothing is listening".
    static func listenerKey(for service: ServiceRecord, now: Date) -> Key? {
        guard !service.state.isTerminal else { return nil }
        guard !service.declaredPorts.isEmpty else { return nil }
        guard service.evidence.portScanRan else { return nil }
        guard service.evidence.processExists != false else { return nil }
        guard !service.evidence.isStale(now: now, tolerance: staleTolerance) else { return nil }
        let missing = service.declaredPorts.filter { !Set(service.evidence.listeningPorts).contains($0) }
        guard !missing.isEmpty else { return nil }
        return Key(category: .listener, subject: service.id)
    }

    // MARK: Events

    static func boundEvents(_ events: [ServiceEvent], now: Date) -> [ServiceEvent] {
        let cutoff = now.addingTimeInterval(-recencyWindow)
        let skew: TimeInterval = 60
        return events
            .filter { $0.ts >= cutoff && $0.ts <= now.addingTimeInterval(skew) }
            .sorted {
                if $0.ts != $1.ts { return $0.ts > $1.ts }
                return $0.seq > $1.seq
            }
            .prefix(maxEvents)
            .map { $0 }
    }

    static func attach(_ events: [ServiceEvent],
                       to drafts: inout [Key: Draft],
                       servicesByID: [String: ServiceRecord]) {
        for event in events {
            for key in Array(drafts.keys) where matches(event, key: key) {
                var draft = drafts[key] ?? Draft(key: key)
                append(event, to: &draft)
                if draft.service == nil, let id = event.serviceID {
                    draft.service = servicesByID[id]
                }
                drafts[key] = draft
            }
        }
    }

    /// Port conflicts and unmanaged leaks are offered only when evidence
    /// exists. Crash recurrence is offered when the bounded log shows a
    /// pattern (two or more), even if the process is currently up.
    static func addEventOnlyDrafts(_ events: [ServiceEvent],
                                   to drafts: inout [Key: Draft],
                                   servicesByID: [String: ServiceRecord]) {
        var crashCounts: [String: [ServiceEvent]] = [:]
        var daemonCrashes: [ServiceEvent] = []
        for event in events {
            switch event.kind {
            case .portViolation:
                guard let id = event.serviceID, !id.isEmpty else { continue }
                let key = Key(category: .port, subject: id)
                var draft = drafts[key] ?? Draft(key: key, service: servicesByID[id])
                append(event, to: &draft)
                if draft.service == nil { draft.service = servicesByID[id] }
                drafts[key] = draft
            case .becameUnmanaged:
                // Legacy unmanaged events have no process identity. Do not
                // merge unrelated processes or guess identity from free text.
                guard let subject = event.serviceID, !subject.isEmpty else { continue }
                let key = Key(category: .unmanaged, subject: subject)
                var draft = drafts[key] ?? Draft(key: key, service: servicesByID[subject])
                append(event, to: &draft)
                if draft.service == nil { draft.service = servicesByID[subject] }
                drafts[key] = draft
            case .crashed:
                guard let id = event.serviceID, !id.isEmpty else { continue }
                crashCounts[id, default: []].append(event)
            case .daemonCrashed:
                daemonCrashes.append(event)
            default:
                continue
            }
        }
        for (id, matched) in crashCounts where matched.count >= 2 {
            let key = Key(category: .crash, subject: id)
            var draft = drafts[key] ?? Draft(key: key, service: servicesByID[id])
            for event in matched { append(event, to: &draft) }
            drafts[key] = draft
        }
        if daemonCrashes.count >= 2 {
            let key = Key(category: .crash, subject: "daemon")
            var draft = drafts[key] ?? Draft(key: key)
            for event in daemonCrashes { append(event, to: &draft) }
            drafts[key] = draft
        }
    }

    static func matches(_ event: ServiceEvent, key: Key) -> Bool {
        switch key.category {
        case .health:
            return event.kind == .healthFailed && event.serviceID == key.subject
        case .crash:
            if key.subject == "daemon" { return event.kind == .daemonCrashed }
            guard event.serviceID == key.subject else { return false }
            return event.kind == .crashed
        case .lease:
            guard event.serviceID == key.subject else { return false }
            return event.kind == .leaseExpiring || event.kind == .leaseExpired || event.kind == .maxRuntimeExceeded
        case .listener:
            return false
        case .port:
            return event.kind == .portViolation && event.serviceID == key.subject
        case .unmanaged:
            guard event.kind == .becameUnmanaged else { return false }
            return event.serviceID == key.subject
        }
    }

    static func append(_ event: ServiceEvent, to draft: inout Draft) {
        if event.seq != 0, draft.events.contains(where: { $0.seq == event.seq }) { return }
        if event.seq == 0,
           draft.events.contains(where: {
               $0.seq == 0 && $0.ts == event.ts && $0.kind == event.kind && $0.detail == event.detail
           }) { return }
        draft.events.append(event)
    }

    static func isSupported(_ draft: Draft, now: Date) -> Bool {
        switch draft.key.category {
        case .health:
            if draft.attention != nil { return true }
            if draft.service?.state == .unhealthy { return true }
            if let service = draft.service,
               service.evidence.healthCheckRan,
               service.evidence.healthPassed == false,
               !service.evidence.isStale(now: now, tolerance: staleTolerance) {
                return true
            }
            return false
        case .crash:
            if draft.attention != nil { return true }
            if draft.service?.state == .crashed { return true }
            return draft.events.count >= 2
        case .lease:
            if draft.attention != nil { return true }
            if draft.service?.state == .expiring || draft.service?.state == .expired { return true }
            if let service = draft.service, !service.state.isTerminal, service.leaseExpiresAt <= now {
                return true
            }
            return false
        case .listener:
            guard let service = draft.service else { return false }
            return listenerKey(for: service, now: now) != nil
        case .port:
            return draft.events.contains { $0.kind == .portViolation }
        case .unmanaged:
            if draft.attention != nil { return true }
            return draft.events.contains { $0.kind == .becameUnmanaged }
        }
    }

    // MARK: Render

    static func suggestion(from draft: Draft, now: Date) -> TroubleshootingSuggestion {
        let occurrences = draft.events.count
        return TroubleshootingSuggestion(
            id: draft.key.id,
            title: clip(title(for: draft, now: now), maxLineChars),
            evidence: clip(evidence(for: draft, now: now), maxEvidenceChars),
            checks: boundLines(checks(for: draft), maxCount: maxChecks),
            remedies: boundLines(remedies(for: draft, now: now), maxCount: maxRemedies),
            occurrences: occurrences)
    }

    static func title(for draft: Draft, now: Date) -> String {
        if let title = draft.attention?.title, !title.isEmpty { return title }
        let name = draft.service?.friendlyName ?? draft.key.subject
        switch draft.key.category {
        case .health:
            return "\(name): health check failing"
        case .crash:
            if draft.key.subject == "daemon" { return "The controller has been restarting" }
            if draft.service?.state == .crashed { return "\(name) crashed" }
            return "\(name): repeated recorded crashes"
        case .lease:
            if let service = draft.service, service.leaseExpiresAt > now, service.state != .expired {
                return "\(name): lease expiring"
            }
            return "\(name): lease expired"
        case .listener:
            return "\(name): declared port not listening"
        case .port:
            return "\(name): port violation"
        case .unmanaged:
            return "Unmanaged process \(name)"
        }
    }

    static func evidence(for draft: Draft, now: Date) -> String {
        var parts: [String] = []
        if !draft.events.isEmpty {
            let kinds = Dictionary(grouping: draft.events, by: \.kind.rawValue)
                .map { "\($0.value.count) \($0.key)" }
                .sorted()
            let n = draft.events.count
            parts.append("\(n) matching event\(n == 1 ? "" : "s") in the bounded recent log (\(kinds.joined(separator: ", "))).")
            if let latest = draft.events.max(by: {
                $0.ts < $1.ts || ($0.ts == $1.ts && $0.seq < $1.seq)
            }), !latest.detail.isEmpty {
                parts.append("Latest: \(clip(latest.detail, 60)).")
            }
        }
        if let service = draft.service {
            parts.append("State \(service.state.rawValue).")
            parts.append(contentsOf: recordEvidence(service, category: draft.key.category, now: now))
        }
        if draft.key.category == .unmanaged {
            parts.append("Recurrence cannot be attributed when legacy events lack a process identity.")
        }
        if let item = draft.attention {
            parts.append("Attention \(clip(item.id, 60)): \(clip(item.title, 80)) — \(clip(item.detail, 160)).")
        }
        return parts.joined(separator: " ")
    }

    static func recordEvidence(_ service: ServiceRecord, category: Category, now: Date) -> [String] {
        switch category {
        case .health:
            var parts: [String] = []
            switch service.evidence.processExists {
            case true?: parts.append("Process is present.")
            case false?: parts.append("Process is not present.")
            case nil: parts.append("Process existence is unavailable.")
            }
            if service.evidence.healthCheckRan {
                if service.evidence.isStale(now: now, tolerance: staleTolerance) {
                    parts.append("Health-check evidence is stale and is not a current result.")
                } else if service.evidence.healthPassed == true {
                    parts.append("Recorded health check passed; process presence is not a health result.")
                } else if service.evidence.healthPassed == false {
                    let detail = service.evidence.healthDetail.map { " (\(clip($0, 80)))" } ?? ""
                    parts.append("Recorded health check failed\(detail); process presence is not a health result.")
                } else {
                    parts.append("Health check ran with no recorded pass/fail; process presence is not a health result.")
                }
            } else {
                parts.append("No health check has run; process presence is not a health result.")
            }
            if service.consecutiveHealthFailures > 0 {
                parts.append("Consecutive recorded failures: \(service.consecutiveHealthFailures).")
            }
            return parts
        case .crash:
            guard let code = service.lastExitCode else { return [] }
            if code < 0 { return ["Last recorded exit: killed by signal \(-Int64(code))."] }
            return ["Last recorded exit code \(code)."]
        case .lease:
            var parts: [String] = []
            let remaining = service.leaseExpiresAt.timeIntervalSince(now)
            if remaining <= 0 {
                parts.append("Lease expired \(Fmt.relative(service.leaseExpiresAt, now: now)).")
            } else {
                parts.append("Lease remaining \(Fmt.duration(remaining)).")
            }
            if service.claimed {
                parts.append("Claimed, not launched — the controller does not reap it.")
            } else if service.state == .paused {
                parts.append("Paused: retains resources; expiry cleanup is deferred until resumed.")
            } else {
                parts.append("Controller-launched: an unrenewed running lease is reaped.")
            }
            return parts
        case .listener:
            let missing = service.declaredPorts.filter { !Set(service.evidence.listeningPorts).contains($0) }
            return [
                "Declared \(Fmt.ports(service.declaredPorts)); listening \(Fmt.ports(service.evidence.listeningPorts)); missing \(Fmt.ports(missing)).",
            ]
        case .port:
            if service.evidence.portScanRan,
               !service.evidence.isStale(now: now, tolerance: staleTolerance) {
                return ["Declared \(Fmt.ports(service.declaredPorts)); listening \(Fmt.ports(service.evidence.listeningPorts))."]
            }
            return []
        case .unmanaged:
            return []
        }
    }

    static func checks(for draft: Draft) -> [String] {
        switch draft.key.category {
        case .health:
            return [
                "Compare the recorded health-check result with the configured target on the service record.",
                "Review recent healthFailed events for this service in the event log.",
                "Confirm whether a health check is configured; process presence is not a health result.",
            ]
        case .crash:
            if draft.key.subject == "daemon" {
                return [
                    "Count daemonCrashed events in the bounded recent log; one exit is not a loop.",
                    "Inspect the recorded controller start/stop sequence; do not assume listed services are healthy.",
                ]
            }
            return [
                "Inspect the recorded exit status and recent crashed or restarted events for this service.",
                "Confirm the process identity on the record before treating a pid as the same process.",
            ]
        case .lease:
            return [
                "Read the recorded lease expiry and most recent renewal time on the service record.",
                "Check whether the record is claimed or controller-launched; that decides who can stop it.",
            ]
        case .listener:
            return [
                "Compare declared ports with the last port-scan result on the service record.",
                "If the scan has not run or the evidence is stale, treat listening state as unavailable.",
            ]
        case .port:
            return [
                "Read the registry record for this service before looking at the process table.",
                "A portViolation event names a listener outside the allowed set; it is not a licence to signal anyone else.",
            ]
        case .unmanaged:
            return [
                draft.attention?.id.hasPrefix("leaked-") == true
                    ? "Identify the owner: the controller started this work, but it outlived its record and is no longer a signalling target."
                    : "Identify the owner from the attention detail and recorded command; this process is currently unmanaged.",
                "Claiming records ownership for visibility and does not grant signalling authority.",
            ]
        }
    }

    static func remedies(for draft: Draft, now: Date) -> [String] {
        let claimed = draft.service?.claimed == true
        if [.health, .crash, .lease, .port].contains(draft.key.category),
           draft.service == nil, draft.key.subject != "daemon" {
            return ["Locate and refresh the current service record before deciding on a remedy. Missing ownership evidence grants no controller signalling authority."]
        }
        switch draft.key.category {
        case .health:
            if claimed {
                return [
                    "The controller does not signal claimed processes. Inspect and recover it where you started it.",
                    "Do not treat process existence as proof the application is healthy.",
                ]
            }
            return [
                "After inspecting the failed check, a controller-launched service can be restarted through fleetctl with operator approval.",
                "Do not treat process existence as proof the application is healthy.",
            ]
        case .crash:
            if draft.key.subject == "daemon" {
                return [
                    "Investigate the recorded abnormal controller exits; do not signal unmanaged processes while doing so.",
                ]
            }
            if claimed {
                return [
                    "The controller will not restart a claimed process. Recover it where you started it.",
                ]
            }
            return [
                "After inspecting the exit, a controller-launched service can be restarted through fleetctl with operator approval.",
            ]
        case .lease:
            if claimed || (draft.service == nil && draft.attention?.detail.contains("Claimed") == true) {
                return [
                    "The operator can renew the visibility record if work is needed; process changes belong to its owner outside this handoff.",
                    "Claimed records are not reaped; the controller will not stop them.",
                ]
            }
            if draft.service?.state == .paused {
                return ["Paused work retains resources; expiry cleanup is deferred until resumed. A needed lease can be renewed through fleetctl with operator approval."]
            }
            if let service = draft.service, service.leaseExpiresAt > now, service.state != .expired {
                return [
                    "With operator approval, fleetctl renew can extend needed work; otherwise the running service is stopped when its lease lapses.",
                ]
            }
            return [
                "With operator approval, fleetctl renew can extend needed work; renewal alone does not restart a service already reaped.",
                "An unrenewed controller-launched service is reaped; that is the lease working, not a failure of the reaper.",
            ]
        case .listener:
            return [
                "Inspect the service's bind configuration against the declared ports on the record.",
                "Do not signal an unmanaged listener to free a port; only a controller-launched holder is a candidate for fleetctl, and only with approval.",
            ]
        case .port:
            if claimed {
                return ["This is a claimed record. The controller cannot stop or restart it; inspect its bind configuration where it was started."]
            }
            return [
                "For a controller-launched holder, an operator-approved fleetctl stop or an owner-reviewed bind configuration change are options.",
                "If the holder is unmanaged, stop: this product does not signal a process it did not start.",
            ]
        case .unmanaged:
            return [
                "Unmanaged and leaked processes are observation-only in this handoff; their owners decide on recovery outside FleetConsole.",
                "fleetctl claim records ownership for visibility and grants no stop, restart, pause, kill or reap authority.",
            ]
        }
    }

    static func boundLines(_ lines: [String], maxCount: Int) -> [String] {
        Array(lines.prefix(maxCount).map { clip($0, maxLineChars) }.filter { !$0.isEmpty })
    }

    static func clip(_ text: String, _ max: Int) -> String {
        let safe = String(text.unicodeScalars.map { scalar -> Character in
            if CharacterSet.controlCharacters.contains(scalar) || (0x202A...0x202E).contains(scalar.value)
                || (0x2066...0x2069).contains(scalar.value) { return " " }
            return Character(String(scalar))
        })
        guard max > 1, safe.count > max else { return safe }
        let end = safe.index(safe.startIndex, offsetBy: max - 1)
        return String(safe[..<end]) + "…"
    }
}
