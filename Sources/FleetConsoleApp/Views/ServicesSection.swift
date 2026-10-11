import SwiftUI
import AppKit
import FleetCore

struct ServicesSection: View {
    @Bindable var model: AppModel
    @Binding var expanded: String?
    @Binding var pendingAction: DestructiveAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Managed Services",
                          subtitle: "\(model.activeServices.count) active") {
                IconButton(symbol: "arrow.triangle.2.circlepath", help: "Run a reconciliation sweep now") {
                    model.reconcileNow()
                }
            }

            if model.activeServices.isEmpty {
                Text(model.connected
                     ? "No managed services. Launch work through fleetctl to track its owner, logs and lease."
                     : "Controller unavailable — service state is unknown.")
                    .font(FleetFont.subtitle)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, FleetMetrics.gutter)
                    .padding(.vertical, 4)
            }

            ForEach(model.activeServices) { row in
                ServiceRowView(row: row, model: model, expanded: $expanded, pendingAction: $pendingAction)
            }

            if !model.unmanaged.isEmpty {
                SectionHeader(title: "Other Background Processes",
                              subtitle: "\(model.unmanaged.count) · not managed by FleetConsole")
                ForEach(model.unmanaged) { process in
                    UnmanagedRowView(process: process, model: model, expanded: $expanded)
                }
            }
        }
    }
}

struct ServiceRowView: View {
    @Bindable var row: ServiceRow
    let model: AppModel
    @Binding var expanded: String?
    @Binding var pendingAction: DestructiveAction?

    private var service: ServiceRecord { row.record }
    private var isStale: Bool { service.evidence.isStale(tolerance: model.staleTolerance) }

    var body: some View {
        DisclosureRow(id: service.id, expanded: $expanded,
                      help: "\(service.state.label) — \(service.purpose)") {
            FleetRowLabel(icon: Iconography.service(service),
                          tone: isStale ? .unknown : service.state.tone,
                          badge: service.state.needsAttention ? service.state.tone : nil,
                          title: service.friendlyName,
                          subtitle: "\(service.ownerAgent) · \(service.projectFolderName)",
                          trailingText: Fmt.duration(service.uptime),
                          trailingMono: true) {
                if model.busyServiceIDs.contains(service.id) {
                    ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 14)
                }
                // Provenance, not status: how the record entered the registry has
                // no good/bad axis, and it decides what the row's verbs can do.
                // `.neutral` for the same reason the VLAN tag is neutral.
                if service.claimed {
                    Tag(text: "Claimed", tone: .neutral)
                }
                if service.state == .expired || service.state == .expiring {
                    Tag(text: service.state == .expired ? "Expired" : leaseCountdown,
                        tone: service.state == .expired ? .bad : .warn)
                }
                Text(Fmt.ports(service.effectivePorts, limit: 1))
                    .font(FleetFont.mono())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        } detail: {
            ServiceDetail(service: service, model: model, pendingAction: $pendingAction, isStale: isStale)
        }
    }

    private var leaseCountdown: String {
        _ = model.clockTick   // 1 Hz redraw for the countdown only
        return service.leaseRemaining > 0 ? Fmt.duration(service.leaseRemaining) : "Expired"
    }
}

/// Expanded detail: ownership, evidence, resources, lease and the safe actions.
struct ServiceDetail: View {
    let service: ServiceRecord
    let model: AppModel
    @Binding var pendingAction: DestructiveAction?
    let isStale: Bool

    @State private var events: [ServiceEvent] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(service.state.label)
                    .font(FleetFont.subtitle.weight(.semibold))
                    .foregroundStyle(service.state.tone.ink)
                if isStale {
                    Text("· status not refreshed recently")
                        .font(FleetFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            EvidenceChips(evidence: service.evidence, health: service.health, stale: isStale)

            Group {
                KeyValue(key: "Purpose", value: service.purpose)
                KeyValue(key: "Owner", value: service.ownerAgent)
                KeyValue(key: "Project", value: service.cwd, monospaced: true)
                KeyValue(key: "Command", value: service.commandLine, monospaced: true)
                KeyValue(key: "PID", value: "\(service.pid.map(String.init) ?? "—") (group \(service.pgid.map(String.init) ?? "—"))", monospaced: true)
                KeyValue(key: "Ports", value: portsDescription, monospaced: true)
                KeyValue(key: "Started", value: "\(Fmt.relative(service.startedAt)) · uptime \(Fmt.duration(service.uptime))")
                KeyValue(key: "Resources", value: "\(Fmt.cpu(service.resources.cpuPct)) CPU · \(Fmt.mem(service.resources.memMB)) · \(service.resources.processCount) proc")
                KeyValue(key: "Lease", value: leaseDescription)
                if service.restartCount > 0 {
                    KeyValue(key: "Restarts", value: "\(service.restartCount)")
                }
                if !service.budgetBreaches.isEmpty {
                    KeyValue(key: "Budget", value: service.budgetBreaches.joined(separator: "; "))
                }
                if let detail = service.evidence.healthDetail {
                    KeyValue(key: "Health", value: detail)
                }
            }

            if !events.isEmpty {
                Divider().padding(.vertical, 2)
                Text("Recent activity")
                    .font(FleetFont.micro)
                    .foregroundStyle(SurfaceInk.secondary)
                ForEach(events.prefix(5)) { event in
                    HStack(alignment: .top, spacing: 5) {
                        Circle()
                            .fill(event.kind.isBad
                                  ? StatusTone.warn.color
                                  : StatusTone.unknown.color)
                            .frame(width: 4, height: 4)
                            .padding(.top, 4)
                        Text(Fmt.relative(event.ts))
                            .font(FleetFont.micro)
                            .foregroundStyle(SurfaceInk.secondary)
                            .frame(width: 54, alignment: .leading)
                        Text(event.kind.label)
                            .font(FleetFont.micro)
                            .frame(width: 92, alignment: .leading)
                        Text(event.detail)
                            .font(FleetFont.micro)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            if !service.cpuHistory.isEmpty {
                HStack(spacing: 10) {
                    Sparkline(values: service.cpuHistory, tone: .good, label: "CPU",
                              current: Fmt.cpu(service.resources.cpuPct))
                    Sparkline(values: service.memHistory, tone: .neutral, label: "MEM",
                              current: Fmt.mem(service.resources.memMB))
                }
                .padding(.top, 2)
            }

            RowActions {
                Button("Logs") { openLogs() }
                Button("Project Folder") { model.revealInFinder(service.cwd) }
                Button("Renew Lease") { model.renew(service) }
                // Absent, not disabled, and not merely left to fail at the daemon:
                // a claimed record is one the controller did not start, so every
                // signal verb is refused on the wire. Drawing five buttons that can
                // only return an error is the same mistake as a Full Screen menu
                // item on a window that refuses full screen.
                if service.isSignallableByController {
                    if service.state == .paused {
                        Button("Resume") { model.resume(service) }
                    } else {
                        Button("Pause") { model.pause(service) }
                    }
                    Button("Restart") { pendingAction = DestructiveAction(kind: .restart, service: service) }
                    Button("Stop") { pendingAction = DestructiveAction(kind: .stop, service: service) }
                        .foregroundStyle(ConsoleColor.destructive)
                    Button("Kill") { pendingAction = DestructiveAction(kind: .kill, service: service) }
                        .foregroundStyle(ConsoleColor.destructive)
                }
            }
            if let refusal = service.signalRefusal {
                Text(refusal)
                    .font(FleetFont.micro)
                    .foregroundStyle(SurfaceInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: service.id) {
            model.loadEvents(serviceID: service.id, limit: 8) { self.events = $0 }
        }
    }

    private var portsDescription: String {
        let declared = service.declaredPorts.isEmpty ? "none declared" : Fmt.ports(service.declaredPorts)
        guard service.evidence.portScanRan else { return "\(declared) · listening not yet scanned" }
        let listening = service.evidence.listeningPorts.isEmpty
            ? "nothing listening"
            : "listening \(Fmt.ports(service.evidence.listeningPorts))"
        return "\(declared) · \(listening)"
    }

    private var leaseDescription: String {
        _ = model.clockTick
        let remaining = service.leaseRemaining
        if remaining <= 0 { return "expired \(Fmt.relative(service.leaseExpiresAt)) — being reaped" }
        return "expires in \(Fmt.duration(remaining)) (ttl \(Fmt.duration(service.leaseTTLSec)))"
    }

    private func openLogs() {
        NSWorkspace.shared.selectFile(service.stdoutPath,
                                      inFileViewerRootedAtPath: (service.stdoutPath as NSString).deletingLastPathComponent)
    }
}

/// Unmanaged processes get visibility and read-only actions only. FleetConsole
/// will not kill something it did not start (threat model T2).
struct UnmanagedRowView: View {
    let process: UnmanagedProcess
    let model: AppModel
    @Binding var expanded: String?

    var body: some View {
        DisclosureRow(id: process.id, expanded: $expanded, help: process.reason.label) {
            FleetRowLabel(icon: Iconography.unmanaged(process),
                          tone: process.formerServiceID != nil ? .warn : .neutral,
                          badge: process.formerServiceID != nil ? .bad : nil,
                          title: process.command,
                          subtitle: "pid \(process.pid) · first seen \(Fmt.relative(process.firstSeen))") {
                if process.formerServiceID != nil { Tag(text: "Leaked", tone: .warn) }
                // A port number is not wrappable text. Unconstrained it broke as
                // ":876" / "5" beside the tag it shares an accessory slot with.
                Text(Fmt.ports(process.ports))
                    .font(FleetFont.mono())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        } detail: {
            VStack(alignment: .leading, spacing: 3) {
                KeyValue(key: "Why flagged", value: process.reason.label)
                KeyValue(key: "Command", value: process.commandLine, monospaced: true)
                KeyValue(key: "User", value: process.user)
                KeyValue(key: "Ports", value: process.ports.isEmpty ? "no listener" : Fmt.ports(process.ports), monospaced: true)
                KeyValue(key: "First seen", value: Fmt.relative(process.firstSeen))
                if let former = process.formerServiceID {
                    KeyValue(key: "Leaked from", value: String(former.prefix(8)), monospaced: true)
                }
                RowActions {
                    Button("Claim") { model.claim(process) }
                        .help("Files this process under an owner, a purpose and a lease so it is "
                              + "supervised instead of merely flagged. The controller still will "
                              + "not signal it — it did not start it.")
                    Button("Reveal in Activity Monitor") { model.openActivityMonitor() }
                    Button("This is expected") { model.markExpected(process.command) }
                        .help("Adds “\(process.command)” to the allow-list in config.json so it stops being flagged.")
                }
            }
        }
    }
}
