import SwiftUI
import FleetCore

struct ProcessModule: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel
    var embedded = false

    @State private var sortOrder: [KeyPathComparator<ProcessRow>] = [
        KeyPathComparator(\.cpuPercent, order: .reverse)
    ]

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

        for comparator in sortOrder.reversed() {
            rows = rows.sorted(using: comparator)
        }
        return rows
    }

    var body: some View {
        let rows = filtered
        let managed = managedByPID
        VStack(alignment: .leading, spacing: 0) {
            header(rowCount: rows.count)
                .padding(.horizontal, ConsoleMetrics.gutter)
                .padding(.top, embedded ? ConsoleMetrics.panelInset : ConsoleMetrics.gutter)
                .padding(.bottom, 10)

            if rows.isEmpty && !console.search.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView {
                    Label("No matching processes", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a process name, PID, user or port number.")
                } actions: {
                    Button("Clear Search") { console.search = "" }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            Table(of: ProcessRow.self, selection: $console.selectedPID, sortOrder: $sortOrder) {
                TableColumn("Process", value: \.name) { row in
                    ProcessNameCell(row: row, managed: managed[row.pid] != nil)
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

                TableColumn("Ports", value: \.ports.count) { row in
                    Text(row.ports.isEmpty ? "—" : ConsoleFmt.ports(row.ports))
                        .font(ConsoleFont.mono(.caption))
                        .monospacedDigit()
                        .foregroundStyle(SurfaceInk.secondary)
                        .lineLimit(1)
                        .accessibilityLabel(row.ports.isEmpty
                                            ? "No listening ports"
                                            : "Ports \(ConsoleFmt.ports(row.ports))")
                }
                .width(min: 60, ideal: 90, max: 160)

                TableColumn("Command") { row in
                    Text(row.commandLine)
                        .font(ConsoleFont.caption)
                        .foregroundStyle(SurfaceInk.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 160, ideal: 320, max: .infinity)
            } rows: {
                ForEach(rows) { row in
                    TableRow(row)
                        .contextMenu {
                            contextMenu(for: row, request: .process(row, model: model))
                        }
                }
            }
            .contextMenu(forSelectionType: Int32.self) { pids in
                if let pid = pids.first, let row = model.processes.row(pid) {
                    Button("Investigate with agent") { model.investigate(.process(row, model: model)) }
                }
            } primaryAction: { pids in
                if let pid = pids.first, let row = model.processes.row(pid) { model.investigate(.process(row, model: model)) }
            }
            .onKeyPress(.return) {
                guard let pid = console.selectedPID, let row = model.processes.row(pid) else { return .ignored }
                model.investigate(.process(row, model: model)); return .handled
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
            }
        }
        .onAppear {
            Task { @MainActor in model.processes.sample() }
        }
    }

    private func header(rowCount: Int) -> some View {
        ModuleControlBar {
            if embedded {
                Text("Processes").font(ConsoleFont.cardTitle).accessibilityAddTraits(.isHeader)
                Text("\(rowCount)").font(ConsoleFont.caption).foregroundStyle(SurfaceInk.secondary)
            }
            Picker("Scope", selection: $console.processScope) {
                ForEach(ConsoleModel.ProcessScope.allCases) { scope in
                    Text(scope.isPremium && !model.license.isUnlocked(.advancedHeatmapFilters)
                         ? "\(scope.rawValue) ◊" : scope.rawValue)
                        .tag(scope)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 180)
            .accessibilityLabel("Process filter")
        }
    }

    private func cpuTone(_ row: ProcessRow) -> StatusTone {
        SystemThresholds.cpuActivity(percent: row.cpuPercent)
    }

    @ViewBuilder
    private func contextMenu(for row: ProcessRow, request: InvestigationRequest) -> some View {
        Button("Investigate with agent") { model.investigate(request) }
        Divider()
        if let serviceID = managedByPID[row.pid],
           let service = model.service(id: serviceID) {
            managedMenu(row: row, service: service)
        } else {
            unmanagedMenu(row: row)
        }
    }

    @ViewBuilder
    private func managedMenu(row: ProcessRow, service: ServiceRecord) -> some View {
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

struct ProcessNameCell: View {
    let row: ProcessRow
    let managed: Bool

    var body: some View {
        HStack(spacing: 8) {
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

enum ProcessActions {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

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
