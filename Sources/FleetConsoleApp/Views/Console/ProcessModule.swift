import SwiftUI
import FleetCore

// Module: Processes — the machine's process table as a first-class citizen.
//
// A native `Table` with column sorting, a scope filter, and a contextual menu
// per row. The action policy is the threat model, rendered honestly:
//
//   * Managed services are signalled *through the controller* (stop, restart,
//     kill) — the app never calls kill(2) itself, so the PID-reuse guard and
//     the audit event both come for free.
//   * Everything else gets read-only verbs — Sample, Copy PID, Reveal in
//     Activity Monitor — plus Claim, which files the process under an owner and
//     a lease without granting anyone the right to signal it. That slot used to
//     hold a permanently disabled "Kill Process" carrying the rule in its
//     tooltip; a control no state can enable is dead chrome however good its
//     explanation, and the rule is better stated by what the menu does.

struct ProcessModule: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel

    @State private var sortOrder: [KeyPathComparator<ProcessRow>] = [
        KeyPathComparator(\.cpuPercent, order: .reverse)
    ]

    /// pid → owning service id, rebuilt when either side changes. A process is
    /// "managed" when its pid *or its process group* matches a live service
    /// record — helpers of `npm run dev` belong to the service that started
    /// them, same rule the supervisor uses.
    private var managedByPID: [Int32: String] {
        var map: [Int32: String] = [:]
        for row in model.activeServices {
            if let pid = row.record.pid { map[pid] = row.id }
            if let pgid = row.record.pgid { map[pgid] = row.id }
        }
        return map
    }

    private var filtered: [ProcessRow] {
        var rows = model.processes.rows

        // A premium scope without a licence silently widens to `all` rather
        // than rendering an empty table under a locked label. The subtitle
        // says what happened, so the fallback is stated, not hidden.
        let scope = console.processScope
        let effectiveScope: ConsoleModel.ProcessScope =
            scope.isPremium && !model.license.isUnlocked(.advancedHeatmapFilters) ? .all : scope

        switch effectiveScope {
        case .all:
            break
        case .managed:
            rows = rows.filter { managedByPID[$0.pid] != nil }
        case .listening:
            rows = rows.filter { !$0.ports.isEmpty }
        case .heavyweight:
            rows = rows.filter { $0.residentBytes > 250_000_000 }
        }

        let query = console.search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            rows = rows.filter { row in
                row.name.localizedCaseInsensitiveContains(query)
                    || row.commandLine.localizedCaseInsensitiveContains(query)
                    || row.user.localizedCaseInsensitiveContains(query)
                    || String(row.pid).contains(query)
                    || row.ports.contains(where: { String($0).contains(query) })
            }
        }

        // KeyPathComparator application: later comparators break earlier ties.
        for comparator in sortOrder.reversed() {
            rows = rows.sorted(using: comparator)
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, ConsoleMetrics.gutter)
                .padding(.top, ConsoleMetrics.gutter)
                .padding(.bottom, 10)

            Table(of: ProcessRow.self, selection: $console.selectedPID, sortOrder: $sortOrder) {
                TableColumn("Process", value: \.name) { row in
                    ProcessNameCell(row: row, managed: managedByPID[row.pid] != nil)
                }
                .width(min: 160, ideal: 220, max: 320)

                TableColumn("PID", value: \.pid) { row in
                    Text(ConsoleFmt.pid(row.pid))
                        .font(ConsoleFont.mono(.callout))
                        .foregroundStyle(.secondary)
                }
                .width(min: 52, ideal: 58, max: 76)

                TableColumn("User", value: \.user) { row in
                    Text(row.user)
                        .font(ConsoleFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 60, ideal: 80, max: 110)

                TableColumn("CPU", value: \.cpuPercent) { row in
                    Text(ConsoleFmt.cpuPercent(row.cpuPercent))
                        .font(ConsoleFont.mono(.callout))
                        .monospacedDigit()
                        // Rule 8: a tone hue used as text on the window
                        // background is the fill colour doing the ink's job.
                        // `ink` is the same hue moved toward the label colour by
                        // the solved minimum that clears AA — which matters most
                        // here, on the one column whose colour *is* the reading.
                        .foregroundStyle(cpuTone(row).ink)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 56, ideal: 62, max: 80)

                TableColumn("Memory", value: \.residentBytes) { row in
                    Text(ConsoleFmt.bytes(row.residentBytes))
                        .font(ConsoleFont.mono(.callout))
                        .monospacedDigit()
                        .foregroundStyle(ConsoleColor.numeral)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 84, max: 110)

                // A process with no ports gets the em dash, drawn — not painted
                // in `Color.clear`, which is what this cell used to do. That
                // renders nothing while still handing VoiceOver a "—" to read,
                // so the column was blank to the eye and dashed to the ear, and
                // an empty cell in a table is ambiguous between "no ports" and
                // "not sampled yet". Rule 4: a fact renders, and says what it is.
                TableColumn("Ports", value: \.ports.count) { row in
                    Text(row.ports.isEmpty ? "—" : ConsoleFmt.ports(row.ports))
                        .font(ConsoleFont.mono(.caption))
                        .monospacedDigit()
                        .foregroundStyle(row.ports.isEmpty ? .tertiary : .secondary)
                        .lineLimit(1)
                        .accessibilityLabel(row.ports.isEmpty
                                            ? "No listening ports"
                                            : "Ports \(ConsoleFmt.ports(row.ports))")
                }
                .width(min: 60, ideal: 90, max: 160)
            } rows: {
                ForEach(filtered) { row in
                    TableRow(row)
                        .contextMenu { contextMenu(for: row) }
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            // The table sits on the page like every other surface: without
            // this it paints AppKit's own table background over the field and
            // the module reads as a panel dropped on top of the window rather
            // than as part of it.
            .scrollContentBackground(.hidden)
        }
        // Deferred to the next runloop tick: `.onAppear` fires while the table
        // is still inside its first NSTableView delegate pass, and any observed
        // state touched here re-enters the delegate mid-reload (macOS logs the
        // "reentrant operation in its NSTableView delegate" warning there, and
        // will assert on it). Sampling from a fresh tick keeps the delegate
        // callback read-only.
        .onAppear {
            Task { @MainActor in model.processes.sample() }
        }
    }

    private var header: some View {
        ModuleHeader(
            title: "Processes",
            subtitle: headerSubtitle,
            symbol: ConsoleModule.processes.symbol
        ) {
            Picker("Scope", selection: $console.processScope) {
                ForEach(ConsoleModel.ProcessScope.allCases) { scope in
                    // Premium scopes are labelled, not locked away: a paywalled
                    // segment you cannot see is a feature you cannot buy. The
                    // picker still lets the selection land on it — the module
                    // applies `all` and says why, which is the same honesty the
                    // Sensors card uses.
                    Text(scope.isPremium && !model.license.isUnlocked(.advancedHeatmapFilters)
                         ? "\(scope.rawValue) ◊" : scope.rawValue)
                        .tag(scope)
                }
            }
            .pickerStyle(.segmented)
            // Four scopes need enough intrinsic room to preserve their labels;
            // when the tool rail is open, 340pt truncates “Heavyweight”.
            .frame(maxWidth: 410)
            .labelsHidden()
        }
    }

    private var headerSubtitle: String {
        let total = model.processes.rows.count
        let shown = filtered.count
        var base = shown == total ? "\(total) processes" : "\(shown) of \(total)"
        // State the fallback from the filter above, where the reader can see
        // it — a scope that widened itself without saying so is a silent lie.
        if console.processScope.isPremium,
           !model.license.isUnlocked(.advancedHeatmapFilters) {
            base += " · \(console.processScope.rawValue) is premium"
        }
        if let captured = model.processes.capturedAt {
            return base + " · sampled " + ConsoleFmt.timestamp(captured)
        }
        return base
    }

    private func cpuTone(_ row: ProcessRow) -> StatusTone {
        SystemThresholds.cpuActivity(percent: row.cpuPercent)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for row: ProcessRow) -> some View {
        if let serviceID = managedByPID[row.pid],
           let service = model.service(id: serviceID) {
            managedMenu(row: row, service: service)
        } else {
            unmanagedMenu(row: row)
        }
    }

    @ViewBuilder
    private func managedMenu(row: ProcessRow, service: ServiceRecord) -> some View {
        // Claimed and launched records are both "managed", and the menu has to say
        // which: the verbs below exist for one and are refused for the other.
        Text(service.claimed
             ? "Claimed by controller — “\(service.friendlyName)” · not signallable"
             : "Managed by controller — “\(service.friendlyName)”")
        Divider()
        if service.isSignallableByController {
            Button("Stop Service…") { model.stop(service) }
            Button("Restart Service…") { model.restart(service) }
            if service.state.isPaused {
                Button("Resume") { model.resume(service) }
            } else {
                Button("Pause (SIGSTOP)") { model.pause(service) }
            }
            Divider()
            Button("Force Kill…") { model.forceKill(service) }
            Divider()
        }
        inspectItems(row: row)
    }

    @ViewBuilder
    private func unmanagedMenu(row: ProcessRow) -> some View {
        // This slot held `Button("Kill Process") {}.disabled(true)` — an empty
        // closure behind a permanent `disabled`, with the rule in its tooltip.
        // No state enabled it, which makes it precisely the dead chrome the
        // design audit already forbids for the Full Screen menu item: a control
        // you can read, cannot press, and will never be able to press.
        //
        // What replaces it is not a shorter menu but the verb that does exist
        // for a process the controller did not start. Claiming files it under an
        // owner, a purpose and a lease so it is supervised and reported on — and
        // it still cannot be signalled, so the rule the disabled button was
        // explaining is intact and is now enforced by what the menu *does*
        // rather than by a sentence about what it does not.
        Button("Claim…") { model.claim(pid: row.pid, name: row.name) }
            .help("File this process under an owner, a purpose and a lease so it is "
                  + "supervised instead of merely listed. The controller still will not "
                  + "signal it — it did not start it.")
        Divider()
        inspectItems(row: row)
    }

    @ViewBuilder
    private func inspectItems(row: ProcessRow) -> some View {
        Button("Sample Process") { ProcessActions.sample(row) }
        Button("Copy PID") { ProcessActions.copy(ConsoleFmt.pid(row.pid)) }
        Button("Copy Command Line") { ProcessActions.copy(row.commandLine) }
        Divider()
        Button("Reveal in Activity Monitor") { model.openActivityMonitor() }
    }
}

// MARK: - Name cell

private struct ProcessNameCell: View {
    let row: ProcessRow
    let managed: Bool

    var body: some View {
        HStack(spacing: 8) {
            // The application's own icon when this process is a bundled app, and
            // the runtime symbol when it is not. `startSignature` is passed for
            // the same reason every signal path re-reads it: pids are recycled,
            // and a cache keyed on the number alone would eventually draw a dead
            // app's icon beside a live process's name.
            AppGlyph(symbol: Iconography.runtime(command: row.name,
                                                 commandLine: row.commandLine,
                                                 hasPorts: !row.ports.isEmpty),
                     fallback: .plain,
                     size: ConsoleMetrics.iconRowGlyph,
                     pid: row.pid,
                     startSignature: row.startSignature)
            Text(row.displayName)
                .font(ConsoleFont.rowTitle)
                .lineLimit(1)
                .truncationMode(.tail)
            if managed {
                Image(systemName: "checkmark.shield.fill")
                    .font(ConsoleFont.marker)
                    .foregroundStyle(.tint)
                    .help("Launched and supervised by the FleetConsole controller")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Actions

enum ProcessActions {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// `/usr/bin/sample` on the pid for one second, written next to the app's
    /// own logs and revealed in Finder. Read-only: sampling observes a process,
    /// it does not signal one.
    static func sample(_ row: ProcessRow) {
        let pid = row.pid
        let name = row.name
        DispatchQueue.global(qos: .userInitiated).async {
            let directory = FleetPaths.logs.appendingPathComponent("samples")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stamp = ConsoleFmt.timestamp(Date()).replacingOccurrences(of: ":", with: "-")
            let output = directory.appendingPathComponent("sample-\(name)-\(pid)-\(stamp).txt")
            let result = Shell.run("/usr/bin/sample",
                                   ["\(pid)", "1", "-file", output.path], timeout: 20)
            DispatchQueue.main.async {
                if result.succeeded, FileManager.default.fileExists(atPath: output.path) {
                    NSWorkspace.shared.selectFile(output.path, inFileViewerRootedAtPath: directory.path)
                } else {
                    NSSound.beep()
                }
            }
        }
    }
}
