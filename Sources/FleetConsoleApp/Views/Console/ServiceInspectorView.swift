import SwiftUI
import FleetCore

// Inspector: one managed service, or one unmanaged process.
//
// The managed view keeps the old inspector's load-bearing parts — the four
// evidence facts, the lease, the placement verdict across the fleet — and adds
// the live resource numbers the console already has. Placement matters here:
// "can this move to another node" is the question a fleet console exists to
// answer, and it is answered with the same hard-constraint rules the evidence
// chips use.

struct ServiceInspectorView: View {
    @Bindable var model: AppModel
    let serviceID: String

    @State private var events: [ServiceEvent] = []
    @State private var logTail: String?
    @State private var logNote: String?

    private var record: ServiceRecord? { model.service(id: serviceID) }

    var body: some View {
        ScrollView {
            if let record {
                VStack(alignment: .leading, spacing: 14) {
                    header(record)
                    evidenceCard(record)
                    activityCard(record)
                    leaseCard(record)
                    placementCard(record)
                    logCard(record)
                    eventsCard
                }
                .padding(14)
            } else {
                ContentUnavailableView("Service record gone",
                                       systemImage: "square.stack.3d.up.slash",
                                       description: Text("The controller no longer has this id."))
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear { reload(record) }
        .onChange(of: serviceID) { reload(record) }
    }

    private func reload(_ record: ServiceRecord?) {
        guard let record else { return }
        model.loadEvents(serviceID: record.id, limit: 40) { events = $0 }
        model.loadLogs(serviceID: record.id, stream: "err") { chunk in
            if let chunk, !chunk.text.isEmpty {
                logTail = String(chunk.text.suffix(2000))
                logNote = nil
            } else {
                logTail = nil
                logNote = "stderr is empty — nothing has complained."
            }
        }
        model.hosts.probe(devices: model.deviceRows.map(\.record))
    }

    // MARK: Header

    private func header(_ record: ServiceRecord) -> some View {
        // `state.label` verbatim: "Running (unverified)" is not a placeholder
        // for "Healthy", and the header is exactly where that would get lost.
        InspectorHeader(symbol: Iconography.service(record), tone: record.state.tone,
                        title: record.friendlyName,
                        subtitle: record.state.label,
                        subtitleKind: .status)
    }

    // MARK: Evidence

    private func evidenceCard(_ record: ServiceRecord) -> some View {
        InspectorCard(title: "Evidence") {
            EvidenceChips(evidence: record.evidence, health: record.health,
                          stale: record.evidence.isStale(tolerance: model.staleTolerance))
            InspectorLine(key: "PID", value: ConsoleFmt.pid(record.pid)
                          + " (group \(ConsoleFmt.pid(record.pgid)))", mono: true)
            InspectorLine(key: "Ports", value: ConsoleFmt.ports(record.effectivePorts)
                          + (record.evidence.listeningPorts.isEmpty && !record.declaredPorts.isEmpty
                             ? " (declared, not yet observed)" : ""), mono: true)
            InspectorLine(key: "Owner", value: record.ownerAgent, mono: true)
            // How the record got here, because it decides what the controller may
            // do to it. Provenance travels with the claim — the same rule the
            // network segments follow.
            InspectorLine(key: "Entered as",
                          value: record.claimed
                              ? "claimed" + (record.claimedAt.map { " \(Fmt.relative($0))" } ?? "")
                              : "launched by the controller")
            InspectorLine(key: "Purpose", value: record.purpose, wrap: true)
            InspectorLine(key: "Command", value: record.commandLine, mono: true, wrap: true)
            // A working directory is a fact you act on — wrapped, not middle-
            // truncated into "/Users/…/src".
            InspectorLine(key: "Directory", value: record.cwd, mono: true, wrap: true)
        }
    }

    // MARK: Activity

    private func activityCard(_ record: ServiceRecord) -> some View {
        InspectorCard(title: "Activity") {
            InspectorLine(key: "CPU", value: ConsoleFmt.cpuPercent(record.resources.cpuPct), mono: true)
            InspectorLine(key: "Memory", value: Fmt.mem(record.resources.memMB), mono: true)
            InspectorLine(key: "Processes", value: "\(record.resources.processCount) in group", mono: true)
            if !record.cpuHistory.isEmpty {
                LoadWaveChart(values: record.cpuHistory.map { min(1, $0 / 100) },
                              tint: record.state.tone.color, height: 44)
            }
        }
    }

    // MARK: Lease

    private func leaseCard(_ record: ServiceRecord) -> some View {
        InspectorCard(title: "Lease") {
            InspectorLine(key: "Expires", value: record.state.isTerminal ? "—"
                          : "\(Fmt.duration(max(0, record.leaseRemaining))) from now", mono: true)
            InspectorLine(key: "TTL", value: Fmt.duration(record.leaseTTLSec), mono: true)
            // "Ran for" once it is over. A terminal record's figure is a span that
            // ended, not a clock still going.
            InspectorLine(key: record.state.isTerminal ? "Ran for" : "Uptime",
                          value: Fmt.duration(record.uptime), mono: true)
            if record.restartCount > 0 {
                InspectorLine(key: "Restarts", value: "\(record.restartCount)", mono: true)
            }
            Text(record.claimed
                 ? "This record was claimed, not launched. The lease still runs and its "
                   + "expiry is still recorded — but nothing is reaped at the end of it, "
                   + "because the controller does not signal a process it did not start."
                 : "The lease is what makes cleanup independent of the agent: unrenewed, "
                   + "the controller reaps the process group whether or not anyone is watching.")
                .font(ConsoleFont.caption)
                .foregroundStyle(SurfaceInk.secondary)
        }
    }

    // MARK: Placement

    @ViewBuilder
    private func placementCard(_ record: ServiceRecord) -> some View {
        let hosts = model.hosts.hosts.filter { !$0.isSelf }
        if !hosts.isEmpty {
            InspectorCard(title: "Could it move?") {
                let traits = WorkloadCatalogue.traits(for: record)
                ForEach(hosts) { host in
                    let verdict = Placement.evaluate(traits, on: host)
                    HStack(spacing: 8) {
                        StatusPip(tone: verdict.outcome.tone, size: 7)
                        Text(host.name)
                            .font(ConsoleFont.subtitle)
                        Spacer()
                        Text(verdict.summary)
                            .font(ConsoleFont.caption)
                            .foregroundStyle(SurfaceInk.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .help(verdict.reasons.joined(separator: "\n"))
                }
                Text("Hard constraints only — architecture, tools, memory headroom, link quality. "
                     + "A placement score you cannot audit is not a score worth showing.")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
            }
        }
    }

    // MARK: Log tail

    private func logCard(_ record: ServiceRecord) -> some View {
        InspectorCard(title: "stderr, last 2 KB") {
            if let logTail {
                Text(logTail)
                    .font(ConsoleFont.mono(.caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(10)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(logNote ?? "Reading…")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
            }
            HStack(spacing: 12) {
                Button("Reveal Logs") { model.revealInFinder(record.stderrPath) }
                Button("Open Directory") { model.revealInFinder(record.cwd) }
            }
            .buttonStyle(.link)
            .font(ConsoleFont.caption)
        }
    }

    // MARK: Events

    private var eventsCard: some View {
        InspectorCard(title: "Timeline") {
            if events.isEmpty {
                Text("No events recorded for this service yet.")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
            } else {
                ForEach(events.prefix(10)) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ConsoleFmt.timestamp(event.ts))
                            .font(ConsoleFont.mono(.caption2))
                            .monospacedDigit()
                            .foregroundStyle(SurfaceInk.secondary)
                            .frame(width: 62, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.kind.label)
                                .font(ConsoleFont.caption.weight(.medium))
                                .foregroundStyle(event.kind.isBad ? StatusTone.bad.ink : ConsoleColor.numeral)
                            if !event.detail.isEmpty {
                                Text(event.detail)
                                    .font(ConsoleFont.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

// MARK: - Unmanaged

struct UnmanagedInspectorView: View {
    @Bindable var model: AppModel
    let unmanagedID: String

    private var process: UnmanagedProcess? {
        model.unmanaged.first { $0.id == unmanagedID }
    }

    var body: some View {
        ScrollView {
            if let process {
                VStack(alignment: .leading, spacing: 14) {
                    InspectorHeader(symbol: Iconography.unmanaged(process), tone: .warn,
                                    title: process.command,
                                    subtitle: "pid \(process.pid) · \(process.user)",
                                    subtitleKind: .identifier)

                    InspectorCard(title: "Why it is listed") {
                        Text(process.reason.label)
                            .font(ConsoleFont.subtitle)
                            .foregroundStyle(.secondary)
                        Text("The reconciler sweeps every 20 seconds. Anything this user runs "
                             + "outside the controller gets visibility here — with no owner, no "
                             + "purpose, no logs and no automatic cleanup.")
                            .font(ConsoleFont.caption)
                            .foregroundStyle(SurfaceInk.secondary)
                    }

                    InspectorCard(title: "Facts") {
                        InspectorLine(key: "Command", value: process.commandLine, mono: true, wrap: true)
                        InspectorLine(key: "Ports", value: ConsoleFmt.ports(process.ports), mono: true)
                        InspectorLine(key: "First seen", value: Fmt.relative(process.firstSeen))
                        InspectorLine(key: "Last seen", value: Fmt.relative(process.lastSeen))
                        if let former = process.formerServiceID {
                            InspectorLine(key: "Formerly", value: "managed as \(former.prefix(8))…", mono: true)
                        }
                    }

                    InspectorCard(title: "Actions") {
                        HStack(spacing: 8) {
                            // Three answers to "what is this doing here", in the
                            // order you reach for them: watch it, expect it,
                            // go and look at it.
                            InspectorActionButton(title: "Claim", symbol: "shield.lefthalf.filled",
                                                  tone: .good) {
                                model.claim(process)
                            }
                            InspectorActionButton(title: "Allow-list", symbol: "checkmark.circle",
                                                  tone: .neutral) {
                                model.markExpected(process.command)
                            }
                            InspectorActionButton(title: "Activity Monitor", symbol: "arrow.up.forward.app",
                                                  tone: .neutral) {
                                model.openActivityMonitor()
                            }
                        }
                        Text("Claiming files this process under an owner, a purpose, a lease and a "
                             + "timeline. It does not hand the controller a stop button: a claimed "
                             + "record is supervised and reported on, never signalled, because "
                             + "FleetConsole did not start it. Allow-listing instead writes the "
                             + "command to config.json and records an event — an explicit, "
                             + "reviewable act, not a hidden dismissal.")
                            .font(ConsoleFont.caption)
                            .foregroundStyle(SurfaceInk.secondary)
                    }
                }
                .padding(14)
            } else {
                ContentUnavailableView("Process gone", systemImage: "questionmark.circle")
            }
        }
        .scrollContentBackground(.hidden)
    }
}
