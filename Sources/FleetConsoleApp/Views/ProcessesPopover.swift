import SwiftUI
import FleetCore

/// One process ranking, with CPU and memory as explicit sort choices.
struct ProcessesContent: View {
    @Bindable var model: AppModel
    var openDashboard: () -> Void

    /// The row awaiting confirmation. Ending a process is not undoable, so it
    /// gets the same treatment the destructive service verbs get.
    @State private var pendingTermination: ProcessRow?
    /// Set when a signal was refused between the click and the syscall.
    @State private var refusal: String?
    @State private var weight: ProcessWeight = .cpu

    private var inventory: ProcessInventory { model.processes }
    private var terminationEnabled: Bool { model.settings.features.allowProcessTermination }

    private static let topCount = 10

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("\(inventory.rows.count) processes")
                        .font(FleetFont.caption).foregroundStyle(.secondary)
                        .help(census)
                    Spacer(minLength: 8)
                    Picker("Rank processes by", selection: $weight) {
                        Text("CPU").tag(ProcessWeight.cpu)
                        Text("Memory").tag(ProcessWeight.memory)
                    }
                    .pickerStyle(.segmented).fixedSize().controlSize(.small)
                    IconButton(symbol: "square.grid.2x2", help: "Open Activity Monitor") {
                        model.openActivityMonitor()
                    }
                }
                .padding(.horizontal, FleetMetrics.gutter)
                .padding(.vertical, 8)
                list(weight.ranked(inventory.rows, limit: Self.topCount), weight: weight)

                Spacer(minLength: 6)
            }
        }
        .frame(maxHeight: FleetMetrics.sectionMaxHeight)
        .alert(item: $pendingTermination) { row in
            Alert(title: Text("End “\(row.displayName)”?"),
                  message: Text("SIGTERM will be sent to pid \(row.pid). "
                                + "The process is asked to exit; it is not forced. "
                                + "Unsaved work in it may be lost."),
                  primaryButton: .destructive(Text("End Process")) { end(row) },
                  secondaryButton: .cancel())
        }
        .alert("Process not ended",
               isPresented: Binding(get: { refusal != nil },
                                    set: { if !$0 { refusal = nil } })) {
            Button("OK", role: .cancel) { refusal = nil }
        } message: {
            Text(refusal ?? "")
        }
    }

    // MARK: - Summary


    /// States worth naming are named; the ordinary majority is not enumerated.
    /// A line reading "612 sleeping" every time would train you to skip it, and
    /// then you would skip it on the day it said "1 zombie".
    private var census: String {
        var parts: [String] = []
        let stopped = inventory.rows.filter { $0.state == .stopped }.count
        let zombies = inventory.rows.filter { $0.state == .zombie }.count
        if zombies > 0 { parts.append("\(zombies) zombie\(zombies == 1 ? "" : "s")") }
        if stopped > 0 { parts.append("\(stopped) stopped") }
        let mine = inventory.rows.filter(\.isOwnedByCurrentUser).count
        parts.append("\(mine) yours")
        if let captured = inventory.capturedAt {
            parts.append("sampled \(Fmt.relative(captured))")
        }
        return parts.joined(separator: " · ")
    }


    // MARK: - Lists

    @ViewBuilder
    private func list(_ rows: [ProcessRow], weight: ProcessWeight) -> some View {
        if rows.isEmpty {
            EmptyLine(text: inventory.capturedAt == nil
                      ? "sampling the process table…"
                      : "nothing measurable on this axis")
        } else {
            ForEach(rows) { row in
                ProcessPopoverRow(
                    row: row,
                    weight: weight,
                    block: inventory.terminationBlock(for: row, enabled: terminationEnabled),
                    inspect: { inspect(row) },
                    end: { pendingTermination = row })
            }
        }
    }

    // MARK: - Actions

    /// Opens the dashboard on Processes with this pid selected. The console
    /// already has a notification for exactly this — the process heatmap uses it
    /// to hand a tile off to the inspector — so the menu bar reuses it rather
    /// than inventing a second route to the same place.
    private func inspect(_ row: ProcessRow) {
        openDashboard()
        NotificationCenter.default.post(
            name: .init("com.fleetconsole.console.selectPID"),
            object: nil, userInfo: ["pid": row.pid])
    }

    private func end(_ row: ProcessRow) {
        if let block = inventory.terminate(row, enabled: terminationEnabled) {
            refusal = block.explanation
        }
    }
}

// MARK: - Row

/// One process, at popover density.
///
/// Composed from `CompactRow`'s vocabulary rather than reimplementing it: fixed
/// height (rule 5 — this list promises not to scroll within its section), the
/// shared `EntityIcon`, the shared hover highlight. What it adds over
/// `CompactRow` is a trailing usage figure that has to stay on the baseline
/// while the number changes, and the two verbs.
private struct ProcessPopoverRow: View {
    let row: ProcessRow
    let weight: ProcessWeight
    let block: ProcessInventory.TerminationBlock?
    let inspect: () -> Void
    let end: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            EntityIcon(symbol: Iconography.runtime(command: row.name,
                                                   commandLine: row.commandLine,
                                                   hasPorts: !row.ports.isEmpty),
                       tone: severity,
                       size: FleetMetrics.iconCompact)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.displayName)
                    .font(FleetFont.rowTitleCompact)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(FleetFont.subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            // The state word, only when it is one you would act on. `neutral`
            // covers running/sleeping/idle, which is every process almost all of
            // the time, and a tag on every row is a tag on no row.
            if row.state.tone != .neutral {
                Tag(text: row.state.label, tone: row.state.tone)
            }

            Text(usage)
                .font(FleetFont.mono(11))
                .monospacedDigit()
                .foregroundStyle(severity == .neutral ? FleetColor.numeral : severity.ink)
                .lineLimit(1)
                .fixedSize()

            // Reserved, not conditional. The verbs still only appear on hover —
            // a row full of buttons you are not pointing at is noise — but the
            // room they take is held on every row, always.
            //
            // Inserting them into the stack instead moved 46pt of content the
            // instant the pointer arrived: the usage figure is the column this
            // list is read down, and it slid left under the cursor while the
            // name beside it truncated and then untruncated as you moved away.
            // The popover header two levels up already reserves this exact slot
            // for this exact reason; a row is the same argument at row scale.
            HStack(spacing: 2) {
                IconButton(symbol: "info.circle", help: "Inspect in the dashboard", action: inspect)
                if hovering && block == nil { endButton }
            }
            .frame(width: FleetMetrics.actionSlot, alignment: .trailing)
        }
        .padding(.horizontal, FleetMetrics.gutter)
        .frame(height: FleetMetrics.compactRowHeight)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .rowBackground(hovering: hovering)
        .padding(.horizontal, FleetMetrics.rowHighlightMargin)
        .help(row.commandLine)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityActions {
            Button("Inspect in dashboard", action: inspect)
            if block == nil { Button("End process", action: end) }
        }
    }

    /// Disabled with its reason attached rather than hidden.
    ///
    /// The Processes module already argues this for its context menu: a menu
    /// that hides the verb invites the question, and a menu that explains it
    /// teaches the model. Here the reason is usually "the flag is off", which
    /// is a thing you can go and change — hiding the button would leave no
    /// trace of the setting existing.
    @ViewBuilder
    private var endButton: some View {
        if let block {
            IconButton(symbol: "xmark.circle", help: block.explanation) {}
                .disabled(true)
        } else {
            IconButton(symbol: "xmark.circle", help: "End this process (SIGTERM)", action: end)
        }
    }

    private var subtitle: String {
        var parts = ["pid \(row.pid)"]
        if !row.isOwnedByCurrentUser { parts.append(row.user) }
        if !row.ports.isEmpty { parts.append(Fmt.ports(row.ports)) }
        return parts.joined(separator: " · ")
    }

    private var usage: String {
        switch weight {
        case .cpu: return String(format: "%.1f%%", row.cpuPercent)
        case .memory: return SystemFmt.size(row.residentBytes)
        }
    }

    /// Colour-coded severity, from the same thresholds the console uses, so
    /// "busy" cannot mean one thing in the menu bar and another in the window.
    /// Memory has no equivalent single-machine threshold — 400 MB is normal for
    /// a browser tab and alarming for a shell — so that list stays achromatic
    /// and lets the ordering carry the ranking.
    private var severity: StatusTone {
        switch weight {
        case .cpu: return SystemThresholds.cpuActivity(percent: row.cpuPercent)
        case .memory: return row.state.tone == .neutral ? .neutral : row.state.tone
        }
    }

    private var accessibilityLabel: String {
        var parts = [row.displayName, "pid \(row.pid)", row.state.label, usage]
        if !row.isOwnedByCurrentUser { parts.append("owned by \(row.user)") }
        return parts.joined(separator: ", ")
    }
}

/// Which of the two weights a list is ranked by.
///
/// Top level rather than nested inside the section: the row is a separate type
/// and has to name it, and a nested enum would mean the row referring back up to
/// the view that happens to own it today.
enum ProcessWeight: Hashable {
    case cpu, memory

    func ranked(_ rows: [ProcessRow], limit: Int) -> [ProcessRow] {
        Array(rows.sorted { lhs, rhs in
            switch self {
            case .cpu:
                return lhs.cpuPercent == rhs.cpuPercent ? lhs.pid < rhs.pid : lhs.cpuPercent > rhs.cpuPercent
            case .memory:
                return lhs.residentBytes == rhs.residentBytes ? lhs.pid < rhs.pid : lhs.residentBytes > rhs.residentBytes
            }
        }.prefix(max(0, limit)))
    }
}
