import SwiftUI
import FleetCore

// Services owns service identity and evidence. Owners remain in each row; the
// agent roster has its own destination, and unmanaged processes stay disclosed.
struct ServicesModule: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel
    var labels: ServiceLabelsStore = .shared

    @State private var pendingAction: DestructiveAction?
    @State private var showUnmanaged = false

    private var query: String { console.search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var managed: [ServiceRow] {
        model.activeServices.filter { labels.matches(query, record: $0.record) }
    }

    private var unmanaged: [UnmanagedProcess] {
        let rows = model.unmanaged
        guard !query.isEmpty else { return rows }
        return rows.filter {
            $0.command.localizedCaseInsensitiveContains(query)
                || $0.commandLine.localizedCaseInsensitiveContains(query)
                || String($0.pid).contains(query)
                || $0.ports.contains(where: { String($0).contains(query) })
        }
    }

    var body: some View {
        List(selection: $console.selectedServiceID) {
            if managed.isEmpty {
                Text(query.isEmpty
                     ? (model.connected ? "No services under management. `fleetctl launch` starts one."
                                        : "Controller unavailable — service state is unknown.")
                     : "No services match “\(query)”.")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
            } else {
                ForEach(managed) { row in
                    ManagedServiceRow(row: row, model: model, labels: labels) { pendingAction = $0 }
                        .tag(row.id)
                }
            }

            if !model.unmanaged.isEmpty {
                DisclosureGroup(isExpanded: $showUnmanaged) {
                    Text("Not started by FleetConsole; never signalled. Select a row to claim or allow-list it.")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(SurfaceInk.secondary)
                    if unmanaged.isEmpty {
                        Text("No unmanaged processes match “\(query)”.")
                            .font(ConsoleFont.caption)
                            .foregroundStyle(SurfaceInk.secondary)
                    }
                    ForEach(unmanaged) { process in
                        UnmanagedRow(process: process)
                            .tag(process.id)
                            .onTapGesture {
                                console.selectedUnmanagedID = process.id
                                console.selectedServiceID = nil
                            }
                    }
                } label: {
                    HStack {
                        Text("Unmanaged")
                        ConsoleBadge(text: "\(unmanaged.count)")
                        Spacer()
                        let leaks = unmanaged.filter { $0.formerServiceID != nil }.count
                        if leaks > 0 {
                            ConsoleBadge(text: "\(leaks) leaked", tone: .warn,
                                         symbol: "exclamationmark.triangle")
                        }
                    }
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                }
                .accessibilityIdentifier("services.unmanaged.disclosure")
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .onChange(of: query) { _, query in
            if !query.isEmpty && !unmanaged.isEmpty { showUnmanaged = true }
        }
        .onChange(of: console.selectedUnmanagedID, initial: true) { _, id in
            if id != nil { showUnmanaged = true }
        }
        .destructiveActionAlert($pendingAction, model: model)
        .actionErrorAlert(model: model)
    }
}

// MARK: - Rows

private struct ManagedServiceRow: View {
    let row: ServiceRow
    let model: AppModel
    let labels: ServiceLabelsStore
    let onAction: (DestructiveAction) -> Void

    private var record: ServiceRecord { row.record }
    private var isStale: Bool { record.evidence.isStale(tolerance: model.staleTolerance) }

    var body: some View {
        HStack(spacing: 10) {
            EntityIcon(symbol: Iconography.service(record),
                       tone: isStale ? .unknown : record.state.tone, size: FleetMetrics.iconRowLarge)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(labels.displayName(for: record))
                        .font(ConsoleFont.rowTitle.weight(.medium))
                        .lineLimit(1)
                    if let color = labels.label(for: record.id).color {
                        ServiceColorTag(color: color).font(ConsoleFont.badge)
                    }
                }
                HStack(spacing: 6) {
                    Text(record.state.label + (isStale ? " · stale" : ""))
                        .foregroundStyle(isStale ? StatusTone.unknown.ink : record.state.tone.ink)
                    if record.claimed { ConsoleBadge(text: "Claimed", tone: .neutral) }
                    Text("\(record.ownerAgent) · \(record.purpose)")
                        .foregroundStyle(SurfaceInk.secondary)
                        .lineLimit(1)
                }
                .font(ConsoleFont.caption)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 8) {
                    if let cpu = record.resources.cpuPct {
                        Text(ConsoleFmt.cpuPercent(cpu)).monospacedDigit()
                    }
                    if let mem = record.resources.memMB {
                        Text(Fmt.mem(mem)).monospacedDigit()
                    }
                }
                .font(ConsoleFont.mono(.caption))
                .foregroundStyle(.secondary)
                Text(record.effectivePorts.isEmpty
                     ? "lease \(Fmt.duration(max(0, record.leaseRemaining)))"
                     : ConsoleFmt.ports(record.effectivePorts))
                    .font(ConsoleFont.mono(.caption2))
                    .monospacedDigit()
                    .foregroundStyle(SurfaceInk.secondary)
            }
            ServiceLabelEditButton(service: record, labels: labels, compact: true)
                .font(ConsoleFont.caption)
        }
        .padding(.vertical, 3)
        .help("\(labels.displayName(for: record)) · recorded as \(record.friendlyName) · \(record.state.label)\(isStale ? " · stale" : "")")
        .contextMenu {
            // A claimed record still keeps lease renewal, never signal controls.
            if record.isSignallableByController {
                Button("Stop…") { onAction(DestructiveAction(kind: .stop, service: record)) }
                Button("Restart…") { onAction(DestructiveAction(kind: .restart, service: record)) }
                if record.state.isPaused {
                    Button("Resume") { model.resume(record) }
                } else {
                    Button("Pause (SIGSTOP)") { model.pause(record) }
                }
            }
            Button("Renew Lease") { model.renew(record) }
            if record.isSignallableByController {
                Divider()
                Button("Force Kill…") { onAction(DestructiveAction(kind: .kill, service: record)) }
            }
        }
    }
}

private struct UnmanagedRow: View {
    let process: UnmanagedProcess

    var body: some View {
        HStack(spacing: 10) {
            EntityIcon(symbol: Iconography.unmanaged(process),
                       tone: process.formerServiceID != nil ? .warn : .neutral,
                       size: FleetMetrics.iconRowLarge)
            VStack(alignment: .leading, spacing: 2) {
                Text(process.command)
                    .font(ConsoleFont.rowTitle.weight(.medium))
                    .lineLimit(1)
                Text(process.reason.label)
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("pid \(process.pid)")
                    .font(ConsoleFont.mono(.caption))
                    .foregroundStyle(.secondary)
                Text(process.ports.isEmpty ? "first seen \(Fmt.relative(process.firstSeen))"
                                           : ConsoleFmt.ports(process.ports))
                    .font(ConsoleFont.mono(.caption2))
                    .monospacedDigit()
                    .foregroundStyle(SurfaceInk.secondary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(process.command), unmanaged, pid \(process.pid)")
    }
}
