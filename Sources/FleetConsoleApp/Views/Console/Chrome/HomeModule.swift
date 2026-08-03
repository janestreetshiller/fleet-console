import SwiftUI
import FleetCore

// The landing surface: what needs attention first, and where to go next.
//
// Five equally-weighted modules answered "where is everything" but never "what
// should I look at" — every screen was one click away and none of them was the
// first one. Home is the answer to the second question, and it does not invent
// one: the controller already decides what needs a decision in
// `computeAttention`, including the crash loop in the controller itself, which
// has no service row anywhere and was previously only findable by reading the
// database by hand. Those items are this view's spine.
//
// The modules are not deleted, or demoted, or merged. They keep ⌘1…⌘n and their
// indices; home is a sixth destination with its own shortcut, and every priority
// row hands off *into* a module with the row already selected.
//
// It lives under Chrome/ only because the file-ownership split during this work
// put new files here; it belongs beside the other modules in Views/Console/.

struct HomeModule: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel

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
            VStack(alignment: .leading, spacing: 16) {
                homeMasthead

                priorityCard
                modulesCard
            }
            .padding(ConsoleMetrics.gutter)
        }
        .scrollContentBackground(.hidden)
    }

    /// Home's header — the same `ModuleHeader` every other surface wears.
    ///
    /// It was previously a centred serif italic largetitle, on the argument that
    /// home is "the one place the window is allowed to have a voice". That was
    /// the wrong call twice. A serif italic appears nowhere else in the app and
    /// in no macOS system surface, so it read as a different application's
    /// screen wedged into this one; and centring it broke the leading-edge
    /// alignment that the sidebar, the toolbar and every card underneath share,
    /// which is the line your eye actually tracks down the window. A landing
    /// page earns attention by what it puts first — the attention list does that
    /// — not by setting its own name in display type.
    private var homeMasthead: some View {
        ModuleHeader(title: "Home", subtitle: subtitle, symbol: "house")
    }

    /// One line that says whether there is anything to do, in the same
    /// precedence order the menu-bar glyph uses — so the window and the status
    /// item cannot tell two different stories about what matters most.
    private var subtitle: String {
        guard model.connected else { return "controller offline" }
        if model.awaitingReplyCount > 0 {
            return "\(model.awaitingReplyCount) awaiting your answer"
        }
        if model.criticalCount > 0 {
            return "\(model.criticalCount) critical · \(model.warningCount) warning"
        }
        if model.warningCount > 0 { return "\(model.warningCount) warning" }
        return "\(model.runningServices.count) services running · nothing needs a decision"
    }

    // MARK: - Priority

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
                }
            }

            if !model.connected {
                // The last snapshot describes what *was* true. Presenting it as
                // current would be exactly the stale claim this app refuses to
                // make, so the list is withheld rather than greyed out.
                PriorityNotice(
                    symbol: "bolt.horizontal.circle",
                    tone: .bad,
                    title: "The controller is not answering",
                    detail: model.connectionError
                        ?? "Nothing here can be trusted as current until fleetd is back.")
            } else {
                if model.awaitingReplyCount > 0 {
                    // Kept apart from the attention list on purpose: the daemon
                    // deliberately never files agent chatter as an incident, and
                    // a question waiting for an answer is a decision only you
                    // can make, not a fault to diagnose.
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
                    }
                }
            }
        }
        .elevatedCard()
    }

    // MARK: - Drill-down

    private var modulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // "Modules", not "Go deeper". The list under it is exactly
                // `ConsoleModule.allCases` — the same six names the toolbar
                // picker and the View menu use — so calling it anything else
                // makes the user map an invented phrase onto a vocabulary the
                // rest of the window already taught them. A section label names
                // its contents; it is not an instruction to the reader.
                Text("Modules")
                    .font(ConsoleFont.cardTitle)
                Spacer()
                // Derived, not written out: the list under this label is
                // `ConsoleModule.allCases`, and a hard-coded "⌘1…⌘5" went stale
                // the moment a sixth module was added.
                Text("⌘1…⌘\(ConsoleModule.allCases.count)")
                    .font(ConsoleFont.mono(.caption))
                    .foregroundStyle(.tertiary)
            }

            ForEach(ConsoleModule.allCases) { module in
                ModuleLink(module: module, detail: detail(for: module)) {
                    console.open(module)
                }
            }
        }
        .elevatedCard()
    }

    /// The live one-liner under each module name — enough to tell you whether
    /// going there is worth it. Every value is one the module itself shows.
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
            // Capacity comes from the volume, not from the throughput
            // differencing that `sampled` describes — so it is gated on having a
            // total, and says nothing when it does not have one.
            guard system.storage.totalBytes > 0 else { return "measuring…" }
            return "\(ConsoleFmt.bytes(system.storage.availableBytes)) free of "
                + "\(ConsoleFmt.bytes(system.storage.totalBytes))"
        case .services:
            // "active", not "managed", because this row is the Services module's
            // own summary and that module's header says active. They are the same
            // number from the same set, and a stopped service is still managed —
            // so "managed" was both the wrong word and the wrong count for it.
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

// MARK: - Rows

/// One priority line. Clicking it is navigation, not selection — home hands you
/// to the surface that can act on the thing, which is why there is no selected
/// state here to disagree with the module's own.
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
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(ConsoleFont.badge)
                    .foregroundStyle(.tertiary)
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

/// A statement rather than a row: nothing to click, because the answer is that
/// there is nothing to go to.
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

/// A module, its live summary, and its shortcut. The badge is the contract:
/// the index shown here is the same one `MainMenu` binds.
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
                    Text(module.rawValue)
                        .font(ConsoleFont.rowTitle)
                        .lineLimit(1)
                    Text(detail)
                        .font(ConsoleFont.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .monospacedDigit()
                }
                Spacer(minLength: 6)
                Text("⌘\(module.shortcutIndex)")
                    .font(ConsoleFont.mono(.caption))
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(ConsoleFont.badge)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(module.rawValue). \(detail)")
        .accessibilityAddTraits(.isButton)
    }
}
