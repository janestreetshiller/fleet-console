import Foundation
import FleetCore

// What the model is told, and where every word of it came from.
//
// This is the substance of the panel. A 4B model asked "why is my service
// broken" is decorative; the same model handed the four evidence pillars, the
// lease, the health spec, the last dozen events and the host's load can actually
// narrow a cause down — because the narrowing is arithmetic over facts, not
// recall. So the assembler's job is to carry evidence with its provenance
// attached, and to say "not checked" wherever the controller has not established
// something. A prompt that flattens an unrun probe into `false` would teach the
// model to invent the same conclusions the UI spent this whole codebase refusing
// to draw.
//
// Two hard constraints shape the output. The wrapper runs its fast profile at
// `ctx 2048` (the banner says so on every run) and the answer has to fit in that
// window too, so the prompt is budgeted in characters and trimmed from the least
// load-bearing end — visibly, with the trim reported. And environment *values*
// never appear: the registry only stores keys (threat model T6), and this is not
// the place that starts leaking them.

// MARK: - Internal error type

/// Thin wrapper so `Result`'s error slot satisfies `Error` conformance without
/// importing a whole enum for what is, in practice, a single diagnostic string.
private struct EvidenceError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

// MARK: - Gathering

/// Everything the panel could learn about the subject before it says a word to a
/// model. All of it comes from the controller.
struct InterpreterEvidence: Sendable {
    /// Set when the controller could not be reached — which is itself a fact
    /// worth putting in the prompt rather than papering over.
    var controllerError: String?
    var generatedAt: Date?
    var tickIntervalSec: Double = 5
    var service: ServiceRecord?
    var events: [ServiceEvent] = []
    var host = HostMetrics()
    var attention: [AttentionItem] = []
    var unmanaged: [UnmanagedProcess] = []
    var otherActive: [ServiceRecord] = []
    var sessions: [AgentSession] = []

    /// Same tolerance the rest of the window uses: three supervisor ticks.
    var staleTolerance: TimeInterval { tickIntervalSec * 3 }
}

/// Pulls a snapshot and, when a service is selected, its timeline.
///
/// Goes to `DaemonClient` directly rather than borrowing `AppModel`: the tool
/// registry builds surfaces with no arguments, and a read-only snapshot request
/// over the same 0600 socket is cheaper than threading the app model through a
/// seam three other panels share.
@MainActor
enum InterpreterEvidenceLoader {
    static func load(serviceID: String?, eventLimit: Int = 24) async -> InterpreterEvidence {
        var evidence = InterpreterEvidence()

        switch await snapshot() {
        case .failure(let reason):
            evidence.controllerError = reason.message
            return evidence
        case .success(let snapshot):
            evidence.generatedAt = snapshot.generatedAt
            evidence.tickIntervalSec = snapshot.daemon.tickIntervalSec
            evidence.attention = snapshot.attention
            evidence.unmanaged = snapshot.unmanaged
            evidence.sessions = snapshot.sessions
            evidence.host = snapshot.devices.first { $0.evidence.isSelf }?.metrics ?? HostMetrics()
            if let serviceID {
                evidence.service = snapshot.services.first { $0.id == serviceID }
            }
            evidence.otherActive = snapshot.activeServices.filter { $0.id != serviceID }
        }

        if let serviceID {
            evidence.events = await events(serviceID: serviceID, limit: eventLimit)
        } else {
            // With nothing selected, the interesting events are the ones that went
            // wrong anywhere on the machine.
            evidence.events = []
        }
        return evidence
    }

    private static func snapshot() async -> Result<Snapshot, EvidenceError> {
        await withCheckedContinuation { continuation in
            DaemonClient.shared.send(RPCRequest(op: .snapshot), timeout: 5) { result in
                switch result {
                case .success(let response):
                    if let snapshot = response.snapshot {
                        continuation.resume(returning: .success(snapshot))
                    } else {
                        continuation.resume(returning: .failure(EvidenceError("the controller answered without a snapshot")))
                    }
                case .failure(let error):
                    continuation.resume(returning: .failure(EvidenceError(error.localizedDescription)))
                }
            }
        }
    }

    private static func events(serviceID: String, limit: Int) async -> [ServiceEvent] {
        await withCheckedContinuation { continuation in
            DaemonClient.shared.send(RPCRequest(op: .events, serviceID: serviceID, limit: limit),
                                     timeout: 5) { result in
                switch result {
                case .success(let response): continuation.resume(returning: response.events ?? [])
                case .failure: continuation.resume(returning: [])
                }
            }
        }
    }
}

// MARK: - The assembled prompt

/// One labelled block of the prompt, kept as structure so the panel can show
/// what it sent as sections rather than as a wall of text.
struct PromptSection: Identifiable, Sendable {
    let id: String
    let title: String
    var lines: [String]
    /// Higher survives. Trimming eats the bottom of this order, so the four
    /// evidence facts outlive the fleet inventory every time.
    let priority: Int

    var rendered: String {
        ([title] + lines.map { "  \($0)" }).joined(separator: "\n")
    }
}

struct AssembledPrompt: Sendable {
    /// Verbatim `--prompt` argument. What the panel displays is this string, not
    /// a pretty-printed cousin of it.
    var text: String
    var sections: [PromptSection]
    /// Sections the budget forced out or cut short, named so the operator can see
    /// what the model was not told.
    var trimmed: [String]
    var budget: Int

    var characters: Int { text.count }
    var overBudget: Bool { characters > budget }
}

enum PromptAssembler {
    /// Character budget for the whole prompt.
    ///
    /// The fast profile runs at `ctx 2048`, shared between prompt and answer.
    /// Technical text — paths, argv, hex, timestamps — runs closer to three
    /// characters per token than four, so 3000 characters is roughly 1000 tokens
    /// and leaves the model about the same again to answer in. Deliberately
    /// conservative: a prompt silently clipped by the runtime would be the
    /// dishonest failure mode, since the answer would still look confident.
    static let budget = 3000

    static func assemble(preset: InterpreterPreset,
                         context: ToolContext,
                         evidence: InterpreterEvidence,
                         now: Date = Date()) -> AssembledPrompt {
        var sections = self.sections(preset: preset, context: context, evidence: evidence, now: now)
        let preamble = self.preamble(preset: preset)
        var trimmed: [String] = []

        // Trim from the least load-bearing end: shorten a long section first,
        // drop it only when it is down to its last two lines.
        while render(preamble: preamble, sections: sections).count > budget {
            guard let index = sections.indices.min(by: { sections[$0].priority < sections[$1].priority })
            else { break }
            if sections[index].lines.count > 2 {
                sections[index].lines.removeLast()
                if !trimmed.contains(sections[index].title) { trimmed.append(sections[index].title) }
            } else {
                let dropped = sections.remove(at: index)
                trimmed.removeAll { $0 == dropped.title }
                trimmed.append("\(dropped.title) (dropped)")
            }
        }

        return AssembledPrompt(text: render(preamble: preamble, sections: sections),
                               sections: sections,
                               trimmed: trimmed,
                               budget: budget)
    }

    private static func render(preamble: String, sections: [PromptSection]) -> String {
        ([preamble] + sections.map(\.rendered)).joined(separator: "\n\n") + "\n"
    }

    // MARK: Preamble

    /// The task and the rules. Never trimmed — the rules are what stop a small
    /// model from turning "not checked" into "broken", and they cost ~450
    /// characters to keep.
    private static func preamble(preset: InterpreterPreset) -> String {
        """
        TASK
          \(preset.instruction)

        RULES
          Four facts are tracked separately and never merged: the process exists, a port \
        is listening, the host is reachable, the health check passed. "not checked" is not \
        "false" — if a fact below was not established, treat it as unknown and say what \
        would establish it.
          Use only the evidence below. Do not invent pids, ports, paths or log lines.
          Do not propose killing or restarting anything the controller did not start.
          Answer in at most eight short lines. No preamble.
        """
    }

    // MARK: Sections

    private static func sections(preset: InterpreterPreset,
                                 context: ToolContext,
                                 evidence: InterpreterEvidence,
                                 now: Date) -> [PromptSection] {
        var sections: [PromptSection] = [subject(context: context, evidence: evidence, now: now)]
        let projectFirst = preset.focus == .project

        if let record = evidence.service {
            sections.append(PromptSection(id: "evidence", title: "EVIDENCE FOR THIS SERVICE",
                                          lines: evidenceLines(record, tolerance: evidence.staleTolerance,
                                                               now: now),
                                          priority: projectFirst ? 70 : 90))
            sections.append(PromptSection(id: "identity", title: "SERVICE",
                                          lines: identityLines(record, now: now),
                                          priority: 75))
            sections.append(PromptSection(id: "health", title: "HEALTH CHECK",
                                          lines: healthLines(record), priority: 65))
            let activity = activityLines(record, now: now)
            if !activity.isEmpty {
                sections.append(PromptSection(id: "activity", title: "RESOURCES AND BUDGET",
                                             lines: activity, priority: 55))
            }
            if !evidence.events.isEmpty {
                sections.append(PromptSection(id: "events", title: "TIMELINE, NEWEST FIRST",
                                             lines: eventLines(evidence.events, now: now),
                                             priority: 45))
            }
        } else {
            sections.append(PromptSection(id: "no-service", title: "NO SERVICE IS SELECTED",
                                          lines: ["The operator has not selected a managed service, so "
                                                  + "there is no per-service evidence. Work from the "
                                                  + "machine-wide facts below."],
                                          priority: 85))
        }

        let project = projectLines(context: context, evidence: evidence)
        if !project.isEmpty {
            sections.append(PromptSection(id: "project", title: "PROJECT DIRECTORY",
                                          lines: project, priority: projectFirst ? 88 : 35))
        }

        sections.append(PromptSection(id: "host", title: "HOST", lines: hostLines(evidence, now: now),
                                      priority: 40))

        let fleet = fleetLines(evidence)
        if !fleet.isEmpty {
            sections.append(PromptSection(id: "fleet", title: "ELSEWHERE ON THIS MACHINE",
                                          lines: fleet, priority: 25))
        }
        return sections
    }

    private static func subject(context: ToolContext, evidence: InterpreterEvidence,
                               now: Date) -> PromptSection {
        var lines = ["subject: \(context.subject)",
                     "working directory: \(context.workingDirectory.path)"]
        if let error = evidence.controllerError {
            lines.append("controller: NOT REACHABLE — \(error). No evidence below was refreshed; "
                         + "treat every fact as unknown.")
        } else if let generatedAt = evidence.generatedAt {
            lines.append("controller snapshot: \(Int(now.timeIntervalSince(generatedAt)))s old, "
                         + "supervisor ticks every \(Int(evidence.tickIntervalSec))s")
        }
        return PromptSection(id: "subject", title: "SUBJECT", lines: lines, priority: 95)
    }

    /// The four pillars, each with what established it. The wording is deliberately
    /// close to the evidence chips' tooltips — one vocabulary, whether the reader
    /// is the operator or a 4B model.
    private static func evidenceLines(_ record: ServiceRecord, tolerance: TimeInterval,
                                     now: Date) -> [String] {
        let facts = record.evidence
        var lines: [String] = []

        switch facts.processExists {
        case .some(true):
            lines.append("process: EXISTS — kill(pid,0) succeeded and the recorded start signature "
                         + "still matches, so this is not a recycled pid")
        case .some(false):
            lines.append("process: GONE — no live process matches the recorded pid and start signature")
        case .none:
            lines.append("process: NOT CHECKED — liveness has never been established for this record")
        }

        if facts.portScanRan {
            lines.append(facts.listeningPorts.isEmpty
                         ? "port: SCANNED, NOTHING LISTENING — the sweep ran and found no port in "
                           + "LISTEN for this process group"
                         : "port: LISTENING on \(Fmt.ports(facts.listeningPorts)) — observed in "
                           + "LISTEN, not merely declared")
        } else {
            lines.append("port: NOT CHECKED — no listener sweep has covered this process group")
        }

        if record.health.kind == .none {
            lines.append("health: NO CHECK CONFIGURED — this service can never be reported healthy, "
                         + "only running-unverified, however alive its process is")
        } else if facts.healthCheckRan {
            let verdict = facts.healthPassed == true ? "PASSED" : "FAILED"
            var line = "health: \(verdict)"
            if let detail = facts.healthDetail, !detail.isEmpty { line += " — \(detail)" }
            if let latency = facts.healthLatencyMs {
                line += " (\(ConsoleFmt.latency(latency)))"
            }
            lines.append(line)
        } else {
            lines.append("health: NOT RUN YET — a check is configured but has not reported")
        }

        if let checkedAt = facts.checkedAt {
            let age = Int(now.timeIntervalSince(checkedAt))
            lines.append(facts.isStale(now: now, tolerance: tolerance)
                         ? "checked \(age)s ago — STALE (older than \(Int(tolerance))s): every fact "
                           + "above describes what was true, not what is true"
                         : "checked \(age)s ago")
        } else {
            lines.append("checked: NEVER — nothing above has been established")
        }

        lines.append("state as recorded: \(record.state.rawValue) — \(record.state.label)")
        return lines
    }

    private static func identityLines(_ record: ServiceRecord, now: Date) -> [String] {
        var lines = [
            "name: \(record.friendlyName)",
            "owner agent: \(record.ownerAgent)",
            "purpose: \(record.purpose)",
            "command: \(record.commandLine)",
            "cwd: \(record.cwd)",
            "pid: \(ConsoleFmt.pid(record.pid)) process group: \(ConsoleFmt.pid(record.pgid))",
            "ports declared: \(Fmt.ports(record.declaredPorts)) "
                + "observed: \(Fmt.ports(record.evidence.listeningPorts))",
            "uptime: \(Fmt.duration(record.uptime)) "
                + "lease: \(record.state.isTerminal ? "—" : Fmt.duration(max(0, record.leaseRemaining)) + " left")"
        ]
        if record.restartCount > 0 { lines.append("restarts: \(record.restartCount)") }
        if let exit = record.lastExitCode { lines.append("last exit code: \(exit)") }
        if record.reapedForExpiry {
            lines.append("reaped for expiry: the owning agent stopped renewing the lease")
        }
        if !record.envKeys.isEmpty {
            // Keys only. The registry never stores the values, and neither does
            // this prompt.
            lines.append("extra environment keys (values are never recorded): "
                         + record.envKeys.joined(separator: ", "))
        }
        _ = now
        return lines
    }

    private static func healthLines(_ record: ServiceRecord) -> [String] {
        let spec = record.health
        guard spec.kind != .none else {
            return ["no health check is configured for this service"]
        }
        var lines = ["kind: \(spec.kind.rawValue)",
                     "target: \(spec.target ?? "unset")",
                     "every \(Int(spec.intervalSec))s, timeout \(Int(spec.timeoutSec))s, "
                        + "\(spec.failureThreshold) consecutive failures before unhealthy"]
        if spec.kind == .http { lines.append("expects HTTP \(spec.expectStatus)") }
        lines.append("consecutive failures now: \(record.consecutiveHealthFailures) "
                     + "(lifetime: \(record.healthFailureCount))")
        return lines
    }

    private static func activityLines(_ record: ServiceRecord, now: Date) -> [String] {
        var lines: [String] = []
        let resources = record.resources
        if let sampledAt = resources.sampledAt {
            lines.append("cpu: \(ConsoleFmt.cpuPercent(resources.cpuPct)) "
                         + "memory: \(Fmt.mem(resources.memMB)) "
                         + "processes in group: \(resources.processCount) "
                         + "(sampled \(Int(now.timeIntervalSince(sampledAt)))s ago)")
        } else {
            lines.append("cpu and memory: NOT SAMPLED — a rate needs two samples and there has not "
                         + "been a second one")
        }
        let budget = record.budget
        var limits: [String] = []
        if let cpu = budget.cpuWarnPct { limits.append("cpu warn \(Int(cpu))%") }
        if let mem = budget.memWarnMB { limits.append("memory warn \(Fmt.mem(mem))") }
        if let runtime = budget.maxRuntimeSec { limits.append("max runtime \(Fmt.duration(runtime))") }
        if !budget.allowedPorts.isEmpty {
            limits.append("allowed ports \(Fmt.ports(budget.allowedPorts))")
        }
        lines.append(limits.isEmpty ? "budget: none declared" : "budget: \(limits.joined(separator: ", "))")
        if !record.budgetBreaches.isEmpty {
            lines.append("breaches: \(record.budgetBreaches.joined(separator: "; "))")
        }
        return lines
    }

    private static func eventLines(_ events: [ServiceEvent], now: Date) -> [String] {
        events
            .sorted { $0.ts > $1.ts }
            .prefix(12)
            .map { event in
                var line = "\(Fmt.relative(event.ts, now: now)) \(event.kind.label)"
                if event.kind.isBad { line += " [bad]" }
                if !event.detail.isEmpty { line += " — \(event.detail)" }
                return line
            }
    }

    private static func projectLines(context: ToolContext, evidence: InterpreterEvidence) -> [String] {
        let root = context.workingDirectory.path
        var lines: [String] = []
        let inProject = evidence.otherActive.filter { $0.cwd == root || $0.cwd.hasPrefix(root + "/") }
        if !inProject.isEmpty {
            lines.append("managed services running out of this directory:")
            for record in inProject.prefix(6) {
                lines.append("  \(record.friendlyName) — \(record.state.rawValue), "
                             + "\(Fmt.ports(record.effectivePorts)), owner \(record.ownerAgent), "
                             + "purpose \(record.purpose)")
            }
        }
        let agents = evidence.sessions.filter { $0.project == root }
        if !agents.isEmpty {
            lines.append("coding agents working here: "
                         + agents.map { "\($0.tool) (pid \($0.pid))" }.joined(separator: ", "))
        }
        if lines.isEmpty && evidence.service == nil {
            lines.append("nothing the controller knows about is running out of this directory")
        }
        return lines
    }

    private static func hostLines(_ evidence: InterpreterEvidence, now: Date) -> [String] {
        var lines: [String] = []
        if evidence.host.hasAny {
            lines.append(evidence.host.line)
            if let collectedAt = evidence.host.collectedAt {
                lines.append("collected \(Int(now.timeIntervalSince(collectedAt)))s ago")
            }
        } else {
            lines.append("host load: NOT COLLECTED — no metrics have been reported for this machine")
        }
        return lines
    }

    private static func fleetLines(_ evidence: InterpreterEvidence) -> [String] {
        var lines: [String] = []
        if !evidence.attention.isEmpty {
            lines.append("needs attention:")
            for item in evidence.attention.prefix(4) {
                lines.append("  [\(item.severity.rawValue)] \(item.title) — \(item.detail)")
            }
        }
        let others = evidence.otherActive.prefix(5)
        if !others.isEmpty {
            lines.append("other managed services: "
                         + others.map { "\($0.friendlyName) (\($0.state.rawValue))" }
                            .joined(separator: ", "))
        }
        if !evidence.unmanaged.isEmpty {
            lines.append("unmanaged listeners the reconciler found: "
                         + evidence.unmanaged.prefix(5)
                            .map { "\($0.command) \(Fmt.ports($0.ports))" }
                            .joined(separator: ", "))
        }
        return lines
    }
}
