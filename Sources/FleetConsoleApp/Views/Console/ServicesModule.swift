import SwiftUI
import FleetCore

// Module: Services — what the controller owns, and what it found that it does
// not own.
//
// Managed services first (they are the point of the app), then unmanaged
// processes (the reconciler's catch), then agents (the owners). Selecting a
// row drives the inspector; destructive verbs stay behind the same alert the
// popover uses, naming the pid and the evidence before anything is signalled.

struct ServicesModule: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel

    @State private var pendingAction: DestructiveAction?

    private var query: String { console.search.trimmingCharacters(in: .whitespaces) }

    private var managed: [ServiceRow] {
        let rows = model.activeServices
        guard !query.isEmpty else { return rows }
        return rows.filter { row in
            let record = row.record
            return record.friendlyName.localizedCaseInsensitiveContains(query)
                || record.ownerAgent.localizedCaseInsensitiveContains(query)
                || record.purpose.localizedCaseInsensitiveContains(query)
                || record.commandLine.localizedCaseInsensitiveContains(query)
                || record.effectivePorts.contains(where: { String($0).contains(query) })
                || (record.pid.map { String($0).contains(query) } ?? false)
        }
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
            Section {
                if managed.isEmpty {
                    Text(query.isEmpty
                         ? "No services under management. `fleetctl launch` starts one."
                         : "No managed services match “\(query)”.")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(managed) { row in
                        ManagedServiceRow(row: row, model: model) { action in
                            pendingAction = action
                        }
                        .tag(row.id)
                    }
                }
            } header: {
                ModuleListHeader(title: "Managed", count: managed.count,
                                 symbol: "square.stack.3d.up")
            }

            Section {
                if unmanaged.isEmpty {
                    Text("No unmanaged listeners or dev-server-shaped processes.")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(unmanaged) { process in
                        UnmanagedRow(process: process)
                            .tag(process.id)
                            .onTapGesture {
                                console.selectedUnmanagedID = process.id
                                console.selectedServiceID = nil
                            }
                    }
                }
            } header: {
                ModuleListHeader(title: "Unmanaged", count: unmanaged.count,
                                 symbol: "questionmark.circle")
            }

            if !model.agentSummaries.isEmpty {
                Section {
                    ForEach(model.agentSummaries) { agent in
                        AgentRow(agent: agent)
                    }
                } header: {
                    ModuleListHeader(title: "Agents", count: model.agentSummaries.count,
                                     symbol: "person.2")
                }
            }
        }
        .listStyle(.inset)
        .overlay(alignment: .top) {
            // The module header sits above the list so the title does not scroll
            // away — every other module does the same.
        }
        .safeAreaInset(edge: .top) {
            ModuleHeader(
                title: "Services",
                subtitle: "\(model.activeServices.count) active · \(model.unmanaged.count) unmanaged",
                symbol: ConsoleModule.services.symbol)
            .padding(.horizontal, ConsoleMetrics.gutter)
            .padding(.vertical, 10)
            .background(.bar)
            .hairline()
        }
        .alert(item: $pendingAction) { action in
            Alert(title: Text(action.title),
                  message: Text(action.message),
                  primaryButton: .destructive(Text(action.kind.rawValue)) {
                      switch action.kind {
                      case .stop: model.stop(action.service)
                      case .restart: model.restart(action.service)
                      case .kill: model.forceKill(action.service)
                      }
                  },
                  secondaryButton: .cancel())
        }
    }
}

// MARK: - Rows

private struct ModuleListHeader: View {
    let title: String
    let count: Int
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(ConsoleFont.caption.weight(.semibold))
            Text(title)
                .font(ConsoleFont.subtitle.weight(.semibold))
            Spacer()
            ConsoleBadge(text: "\(count)")
        }
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}

private struct ManagedServiceRow: View {
    let row: ServiceRow
    let model: AppModel
    let onAction: (DestructiveAction) -> Void

    private var record: ServiceRecord { row.record }

    var body: some View {
        HStack(spacing: 10) {
            EntityIcon(symbol: Iconography.service(record), tone: record.state.tone, size: FleetMetrics.iconRowLarge)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.friendlyName)
                        .font(ConsoleFont.rowTitle.weight(.medium))
                        .lineLimit(1)
                    Text(record.state.label)
                        .font(ConsoleFont.caption)
                        .foregroundStyle(record.state.tone.ink)
                }
                Text("\(record.ownerAgent) · \(record.purpose)")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 8) {
                    if let cpu = record.resources.cpuPct {
                        Text(ConsoleFmt.cpuPercent(cpu))
                            .monospacedDigit()
                    }
                    if let mem = record.resources.memMB {
                        Text(Fmt.mem(mem))
                            .monospacedDigit()
                    }
                }
                .font(ConsoleFont.mono(.caption))
                .foregroundStyle(.secondary)
                Text(record.effectivePorts.isEmpty
                     ? "lease \(Fmt.duration(max(0, record.leaseRemaining)))"
                     : ConsoleFmt.ports(record.effectivePorts))
                    .font(ConsoleFont.mono(.caption2))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            // Renew is the one verb a claimed record keeps: a lease is a promise
            // about how long you expect the thing to be here, and extending it
            // signals nothing to the process.
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
            EntityIcon(symbol: Iconography.unmanaged(process), tone: .warn, size: FleetMetrics.iconRowLarge)
            VStack(alignment: .leading, spacing: 2) {
                Text(process.command)
                    .font(ConsoleFont.rowTitle.weight(.medium))
                    .lineLimit(1)
                Text(process.reason.label)
                    .font(ConsoleFont.caption)
                    .foregroundStyle(.tertiary)
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
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(process.command), unmanaged, pid \(process.pid)")
    }
}

private struct AgentRow: View {
    let agent: AgentSummary

    var body: some View {
        HStack(spacing: 10) {
            // `AppGlyph`, not a bare `EntityIcon`.
            //
            // The popover's agent rows have borrowed the tool's own desktop
            // artwork since `AppGlyph` was written; the dashboard's never did,
            // so the one surface called the dashboard showed a generic person
            // tile for `codex` while the popover two clicks away showed the
            // app's logo. That is the same fact rendered two ways, which is the
            // thing this design system exists to stop.
            //
            // The fallback is the tile it used to draw unconditionally, with
            // the same tone, so an agent with no desktop app is unchanged.
            AppGlyph(symbol: "person.crop.rectangle.stack",
                     fallback: .tile,
                     tone: agent.awaitingReply > 0 ? .warn
                           : agent.needingAttention > 0 ? .bad
                           : agent.running > 0 ? .good : .neutral,
                     size: FleetMetrics.iconRowLarge,
                     agentTool: agent.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.id)
                    .font(ConsoleFont.rowTitle.weight(.medium))
                    .lineLimit(1)
                Text(agent.purposes.first ?? (agent.running > 0 ? "running" : "idle"))
                    .font(ConsoleFont.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if agent.awaitingReply > 0 {
                    ConsoleBadge(text: "\(agent.awaitingReply) awaiting", tone: .warn,
                                 symbol: "questionmark.bubble")
                }
                // Shown whenever the agent owns a record, including when none of
                // them are running. Hiding the count at zero left an agent whose
                // only service had expired with a blank cell beside siblings that
                // had numbers, which reads as a row that failed to draw rather
                // than as a zero. Blank now means one thing: owns no services.
                if agent.owned > 0 {
                    Text("\(agent.running) svc")
                        .font(ConsoleFont.mono(.caption))
                        .monospacedDigit()
                        .foregroundStyle(agent.running > 0 ? AnyShapeStyle(.secondary)
                                                           : AnyShapeStyle(.tertiary))
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .hoverHighlight()
        .contextMenu {
            Text("Agent: \(agent.id)")
            Divider()
            Button("Copy Agent ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(agent.id, forType: .string)
            }
            if !agent.purposes.isEmpty {
                Button("Copy Purposes") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(agent.purposes.joined(separator: "\n"),
                                                   forType: .string)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(agent.id), \(agent.running) services running")
    }
}
