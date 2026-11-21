import SwiftUI
import FleetCore

struct HomeModule: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel
    var fixer: FixAgentSettings = .shared

    private var query: String { console.search.trimmingCharacters(in: .whitespaces) }

    private var attention: [AttentionItem] {
        guard !query.isEmpty else { return model.attention }
        return model.attention.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.detail.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ConsoleMetrics.gutter) {
                WorkspaceHeading(title: "Needs Attention",
                                 detail: "Decisions and controller findings come first. Agent activity and saved tasks follow below.")
                priorityCard
                    .accessibilityIdentifier("home.priority")
                QuantizedCardGrid(minimumCellWidth: 360, maximumColumns: 2) {
                    AgentsContent(model: model, openDashboard: {})
                        .elevatedCard()
                        .accessibilityIdentifier("home.agents")
                    LaterTasksView()
                    modulesCard
                }
            }
            .padding(ConsoleMetrics.gutter)
        }
        .scrollContentBackground(.hidden)
        .actionErrorAlert(model: model)
    }

    @ViewBuilder
    private var priorityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Needs attention")
                    .font(ConsoleFont.cardTitle)
                Spacer()
                if model.connected, !model.attention.isEmpty {
                    ConsoleBadge(text: "\(model.attention.count)",
                                 tone: model.criticalCount > 0 ? .bad : .warn)
                    if let designated = fixer.designated {
                        Button("Send to \(designated.title)") { send(attention) }
                            .controlSize(.small)
                            .help("Write a report of these problems and start \(designated.title) on it in the terminal.")
                            .accessibilityIdentifier("home.fixer.send")
                    }
                }
            }

            if !model.connected {
                PriorityNotice(
                    symbol: "bolt.horizontal.circle",
                    tone: .bad,
                    title: "The controller is not answering",
                    detail: model.connectionError
                        ?? "Nothing here can be trusted as current until fleetd is back.")
            } else {
                if model.awaitingReplyCount > 0 {
                    ForEach(model.awaitingReplies) { message in
                        PriorityRow(symbol: "questionmark.bubble",
                                    tone: .warn,
                                    title: "\(message.agent) is waiting on you",
                                    detail: message.body,
                                    since: message.createdAt) {
                            console.open(.services)
                        }
                    }
                }

                if attention.isEmpty {
                    PriorityNotice(
                        symbol: query.isEmpty ? "checkmark.circle" : "magnifyingglass",
                        tone: query.isEmpty ? .good : .neutral,
                        title: query.isEmpty
                            ? "Nothing needs a decision"
                            : "Nothing matches “\(query)”",
                        detail: query.isEmpty
                            ? "Health checks, leases, budgets, new listeners and device "
                                + "reachability were all checked. Absence is the result."
                            : "\(model.attention.count) items are filtered out.")
                } else {
                    ForEach(attention) { item in
                        PriorityRow(symbol: Iconography.attention(item),
                                    tone: item.severity == .critical ? .bad : .warn,
                                    title: item.title,
                                    detail: item.detail,
                                    since: item.since) {
                            console.reveal(item, model: model)
                        }
                        .contextMenu {
                            if let designated = fixer.designated {
                                Button("Send to \(designated.title)") { send([item]) }
                            }
                        }
                    }
                }
            }
        }
        .elevatedCard()
    }

    private func send(_ items: [AttentionItem]) {
        if let problem = model.sendToFixer(items, openDashboard: {}) { model.actionError = problem }
    }

    private var modulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Explore")
                    .font(ConsoleFont.cardTitle)
                Spacer()
                Text("⌘1…⌘\(ConsoleModule.allCases.count)")
                    .font(ConsoleFont.mono(.caption))
                    .foregroundStyle(SurfaceInk.secondary)
            }

            ForEach([ConsoleModule.overview, .processes, .services]) { module in
                ModuleLink(module: module, detail: detail(for: module)) {
                    console.open(module)
                }
            }
        }
        .elevatedCard()
    }

    private func detail(for module: ConsoleModule) -> String {
        let system = model.system
        switch module {
        case .overview:
            guard system.cpu.sampled else { return "sampling…" }
            return ConsoleFmt.utilPercent(system.cpu.usage) + " CPU · "
                + ConsoleFmt.utilPercent(system.memory.usedShare) + " RAM · "
                + "pressure \(system.memory.pressure.label)"
        case .processes:
            let count = model.processes.rows.count
            guard let captured = model.processes.capturedAt else { return "reading the table…" }
            return "\(count) processes · sampled \(ConsoleFmt.timestamp(captured))"
        case .storage:
            guard system.storage.totalBytes > 0 else { return "measuring…" }
            return "\(ConsoleFmt.bytes(system.storage.availableBytes)) free of "
                + "\(ConsoleFmt.bytes(system.storage.totalBytes))"
        case .services:
            var parts = ["\(model.activeServices.count) active"]
            if !model.unmanaged.isEmpty { parts.append("\(model.unmanaged.count) unmanaged") }
            if !model.agentProfiles.isEmpty { parts.append("\(model.agentProfiles.count) agents") }
            return parts.joined(separator: " · ")
        case .events:
            guard let latest = model.recentEvents.first else { return "no events recorded yet" }
            return "\(ConsoleFmt.timestamp(latest.ts)) · \(latest.kind.label)"
        case .plists:
            return "LaunchAgents · LaunchDaemons — read-only inspection"
        }
    }
}

private struct PriorityRow: View {
    let symbol: String
    let tone: StatusTone
    let title: String
    let detail: String
    let since: Date
    let reveal: () -> Void

    var body: some View {
        Button(action: reveal) {
            HStack(spacing: 10) {
                EntityIcon(symbol: symbol, tone: tone, size: FleetMetrics.iconRowLarge)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ConsoleFont.rowTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(detail)
                        .font(ConsoleFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 6)
                Text(Fmt.relative(since))
                    .font(ConsoleFont.mono(.caption2))
                    .monospacedDigit()
                    .foregroundStyle(SurfaceInk.secondary)
                Image(systemName: "chevron.right")
                    .font(ConsoleFont.badge)
                    .foregroundStyle(SurfaceInk.secondary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityAddTraits(.isButton)
    }
}

private struct PriorityNotice: View {
    let symbol: String
    let tone: StatusTone
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            EntityIcon(symbol: symbol, tone: tone, size: FleetMetrics.iconRowLarge)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ConsoleFont.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(detail)
                    .font(ConsoleFont.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct ModuleLink: View {
    let module: ConsoleModule
    let detail: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: module.symbol)
                    .font(ConsoleFont.rowTitle)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: ConsoleToolMetrics.toggleSize)
                VStack(alignment: .leading, spacing: 1) {
                    Text(module.title)
                        .font(ConsoleFont.rowTitle)
                        .lineLimit(1)
                    Text(detail)
                        .font(ConsoleFont.caption)
                        .foregroundStyle(SurfaceInk.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .monospacedDigit()
                }
                Spacer(minLength: 6)
                Text("⌘\(module.shortcutIndex)")
                    .font(ConsoleFont.mono(.caption))
                    .foregroundStyle(SurfaceInk.secondary)
                Image(systemName: "chevron.right")
                    .font(ConsoleFont.badge)
                    .foregroundStyle(SurfaceInk.secondary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(module.title). \(detail)")
        .accessibilityAddTraits(.isButton)
    }
}
