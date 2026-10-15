import SwiftUI
import Foundation
import Observation
import Charts
import FleetCore

/// Legacy operations stay intact, grouped under one destination.
struct OperationsWorkspace: View {
    let model: AppModel
    let console: ConsoleModel
    private var section: String { console.operationsSection }
    private let sections = ["Services", "Network", "Agents", "Storage", "Events", "Launch Services", "Account"]
    var body: some View {
        VStack(spacing: 8) {
            Picker("Operations", selection: Binding(get: { console.operationsSection }, set: { console.operationsSection = $0 })) {
                ForEach(sections, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu).padding(.horizontal, ConsoleMetrics.gutter)
            switch section {
            case "Network": ScrollView { NetworkGlance(model: model) }
            case "Agents": ScrollView { AgentsContent(model: model, openDashboard: {}) }
            case "Storage": StorageModule(model: model, console: console)
            case "Events": EventsModule(model: model, console: console)
            case "Launch Services": PlistsModule(console: console)
            case "Account": DeviceManagementView(model: model)
            default: ServicesModule(model: model, console: console)
            }
        }
    }
}

struct ProcessWorkspace: View {
    let model: AppModel
    let console: ConsoleModel
    @State private var visualization = "Relationships"
    @State private var scatterMemory: Double?
    private var matchingRows: [ProcessRow] {
        let query = console.search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.processes.rows.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
            || String($0.pid).contains(query) || $0.commandLine.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(spacing: 8) {
            Picker("Process view", selection: $visualization) {
                ForEach(["Relationships", "Table", "Heatmap", "Scatter"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, ConsoleMetrics.gutter)
            switch visualization {
            case "Table": ProcessModule(model: model, console: console)
            case "Heatmap":
                HeatmapView(items: ProcessHeatmap.items(from: matchingRows),
                            summary: "Area: resident memory · color: CPU · groups select their heaviest process", animatesLayout: false, investigationModel: model)
                    .padding(ConsoleMetrics.gutter)
            case "Scatter": scatter
            default: ProcessRelationsView(model: model, console: console)
            }
        }
        .actionErrorAlert(model: model)
    }
    private var scatter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current CPU and resident memory. Select a dot’s process below; proximity does not establish a relationship.")
                .font(ConsoleFont.caption)
            if model.processes.rows.isEmpty { Text("No process observations yet.") }
            Chart(matchingRows.filter { $0.cpuPercent.isFinite && $0.residentBytes >= 0 }) { row in
                PointMark(x: .value("Resident memory (MiB)", Double(row.residentBytes) / 1_048_576),
                          y: .value("Process CPU (%)", row.cpuPercent))
            }
            .chartXSelection(value: $scatterMemory)
            .chartXAxisLabel("Resident memory (MiB)")
            .chartYAxisLabel("Process CPU (%)")
            .frame(minHeight: 200)
            if let memory = scatterMemory,
               let row = matchingRows.min(by: { abs(Double($0.residentBytes) / 1_048_576 - memory) < abs(Double($1.residentBytes) / 1_048_576 - memory) }) {
                Button("Nearest by memory: \(row.displayName) · pid \(row.pid) — inspect") {
                    console.selectedPID = row.pid; console.inspectorRevealed = true
                }
                .investigatable(.process(row, model: model), model: model)
            } else { Text("Select a memory coordinate to inspect its nearest observed process.").font(ConsoleFont.caption) }
        }.padding(ConsoleMetrics.gutter)
    }
}

/// A bounded ego graph: only observed parent/child links, never inferred causal edges.
struct ProcessRelationsView: View {
    let model: AppModel
    let console: ConsoleModel
    @State private var focusPID: Int32?
    private var root: ProcessRow? {
        focusPID.flatMap { model.processes.row($0) }
            ?? model.processes.rows.filter {
                let query = console.search.trimmingCharacters(in: .whitespacesAndNewlines)
                return query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || String($0.pid).contains(query)
            }.max { $0.cpuPercent < $1.cpuPercent }
    }
    private var nodes: [ProcessRow] {
        guard let root else { return [] }
        let ancestors = model.processes.ancestry(of: root, limit: 6).reversed()
        let children = (model.processes.childrenOf[root.pid] ?? []).sorted { $0.cpuPercent > $1.cpuPercent }.prefix(12)
        return Array(ancestors) + [root] + children
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Observed parent → child links").font(ConsoleFont.cardTitle)
                Spacer()
                Button("Focus selected process") { focusPID = console.selectedPID }
                    .disabled(console.selectedPID == nil)
            }
            Text("Parent links use one process-table snapshot. Owner/session badges use separate controller observations. Search chooses a root; relatives remain visible. Links show ancestry, not proof of cause. Up to 6 ancestors and 12 children.")
                .font(ConsoleFont.caption).foregroundStyle(.secondary)
            if let captured = model.processes.capturedAt { Text("Observed \(captured.formatted())").font(ConsoleFont.caption) }
            if nodes.isEmpty { ContentUnavailableView("No process relationships sampled", systemImage: "point.3.connected.trianglepath.dotted") }
            ScrollView([.horizontal, .vertical]) {
                let rows = nodes
                let rootIndex = rows.firstIndex(where: { $0.pid == root?.pid }) ?? 0
                let childCount = max(1, rows.count - rootIndex - 1)
                let graphHeight = CGFloat(childCount) * 90 + 32
                let graphWidth = CGFloat(rootIndex + 2) * 250 + 16
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for (index, child) in rows.enumerated() {
                            guard let parentIndex = rows.firstIndex(where: { $0.pid == child.ppid }) else { continue }
                            var path = Path()
                            let parent = point(parentIndex, rootIndex: rootIndex, height: graphHeight)
                            let child = point(index, rootIndex: rootIndex, height: graphHeight)
                            path.move(to: CGPoint(x: parent.x + 112, y: parent.y))
                            path.addLine(to: CGPoint(x: child.x - 120, y: child.y))
                            path.addLine(to: CGPoint(x: child.x - 127, y: child.y - 4))
                            path.move(to: CGPoint(x: child.x - 120, y: child.y))
                            path.addLine(to: CGPoint(x: child.x - 127, y: child.y + 4))
                            context.stroke(path, with: .color(.secondary), lineWidth: 1)
                        }
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.pid) { index, row in
                        Button {
                            console.selectedPID = row.pid
                            console.inspectorRevealed = true
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(row.displayName) · pid \(row.pid)").font(ConsoleFont.rowTitle)
                                Text("CPU \(ConsoleFmt.cpuPercent(row.cpuPercent)) · \(ConsoleFmt.bytes(row.residentBytes))")
                                    .font(ConsoleFont.caption)
                                if let service = model.activeServices.first(where: { $0.record.pid == row.pid || $0.record.pgid == row.pgid }) {
                                    Text("Service owner: \(service.record.ownerAgent)").font(ConsoleFont.micro)
                                }
                                if let agent = model.sessions.first(where: { $0.pid == row.pid }) {
                                    Text("Detected session: \(agent.tool)").font(ConsoleFont.micro)
                                }
                            }
                            .frame(width: 216, height: 64, alignment: .leading)
                            .padding(.horizontal, 8)
                            .background(.background, in: RoundedRectangle(cornerRadius: 4))
                            .overlay { RoundedRectangle(cornerRadius: 4).stroke(row.pid == root?.pid ? Color.accentColor : Color.secondary, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .investigatable(.process(row, model: model), model: model)
                        .position(point(index, rootIndex: rootIndex, height: graphHeight))
                    }
                }
                .frame(width: graphWidth, height: graphHeight)
            }
        }
        .padding(ConsoleMetrics.gutter)
        .onAppear { if focusPID == nil { focusPID = console.selectedPID } }
        .onChange(of: console.search) { _, _ in focusPID = nil }
    }
    private func point(_ index: Int, rootIndex: Int, height: CGFloat) -> CGPoint {
        if index <= rootIndex { return CGPoint(x: CGFloat(index) * 250 + 124, y: height / 2) }
        return CGPoint(x: CGFloat(rootIndex + 1) * 250 + 124, y: CGFloat(index - rootIndex - 1) * 90 + 48)
    }
}

/// The original instrument page, with the later evidence surfaces added under it.
///
/// `OverviewModule` keeps the viewport it was measured against: a fixed height,
/// no scroll of its own, and the capped process preview the viewport tests host
/// directly. The process map and the interval chart sit on this page, so neither
/// replaces the CPU and memory graphs.
struct OverviewWorkspace: View {
    let model: AppModel
    let console: ConsoleModel
    /// Plots stay above the 89pt floor with the compact process cap, and the
    /// default module column still shows the process map's title under them.
    private static let instrumentHeight: CGFloat = 640

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OverviewViewportGeometry.gap) {
                OverviewModule(model: model, console: console)
                    .frame(height: Self.instrumentHeight)
                ConsolidatedProcessMap(model: model, console: console)
                TrendsWorkspace(model: model, console: console, scrolls: false, showsInstruments: false)
            }
        }
    }
}

/// Area is resident memory and colour is CPU. Search matches the process table:
/// name or command line. Tiles still open the heaviest process.
private struct ConsolidatedProcessMap: View {
    let model: AppModel
    @Bindable var console: ConsoleModel

    private var query: String { console.search.trimmingCharacters(in: .whitespaces) }

    private var rows: [ProcessRow] {
        guard !query.isEmpty else { return model.processes.rows }
        return model.processes.rows.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.commandLine.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let matching = rows
        let items = ProcessHeatmap.items(from: matching)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Process Map")
                    .font(ConsoleFont.cardTitle)
                Spacer()
                Text(query.isEmpty
                     ? "area = resident memory · colour = CPU · tap to inspect"
                     : "\(matching.count) matching \(query.lowercased()) · area = resident memory")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if !query.isEmpty && matching.isEmpty {
                Text("No process matches \(query).")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: ConsoleMetrics.mapHeight, alignment: .top)
            } else if items.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the process table…")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: ConsoleMetrics.mapHeight, alignment: .leading)
            } else {
                HeatmapView(items: items,
                            summary: "Helpers are folded into their parent app. The “Other” tile is "
                                   + "everything below 8 MB or past the fortieth group — rolled up, "
                                   + "never dropped.",
                            animatesLayout: false,
                            investigationModel: model)
                    .frame(height: ConsoleMetrics.mapHeight)
            }
        }
        .elevatedCard()
        .padding(.horizontal, OverviewViewportGeometry.horizontalPadding)
        .accessibilityIdentifier("overview.process-map")
    }
}

/// CPU interval selection joins only real retained process observations by timestamp.
struct TrendsWorkspace: View {
    let model: AppModel
    let console: ConsoleModel
    /// The overview page already scrolls. A nested scroll traps the interval chart.
    var scrolls = true
    /// The instrument graphs are the page above this chart. The sheet is the
    /// standalone entry, used only when this workspace is the whole column.
    var showsInstruments = true
    @State private var selection: ClosedRange<Date>?
    @State private var instruments = false
    private var observations: [ProcessInventory.CapturedProcesses] {
        guard let selection else { return [] }
        return model.processes.observations.filter { selection.contains($0.time) }
    }
    var body: some View {
        Group {
            if scrolls {
                ScrollView { intervalEvidence }
            } else {
                intervalEvidence
            }
        }
        .sheet(isPresented: $instruments) {
            VStack {
                Button("Done") { instruments = false }.keyboardShortcut(.cancelAction)
                OverviewModule(model: model, console: console)
            }.frame(minWidth: 760, minHeight: 620)
        }
        .actionErrorAlert(model: model)
    }

    private var intervalEvidence: some View {
        VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("CPU over time").font(ConsoleFont.cardTitle)
                    Spacer()
                    if showsInstruments {
                        Button("All instruments") { instruments = true }
                    }
                    Button("Clear interval") { selection = nil }.disabled(selection == nil)
                }
                Text("Drag across the plot to select an interval or spike. Process samples use a slower cadence than CPU; their overlap is correlation, not demonstrated cause.")
                    .font(ConsoleFont.caption)
                if model.system.cpuSeries.samples.isEmpty { Text("Waiting for two CPU counter samples.") }
                Chart {
                    ForEach(Array(model.system.cpuSeries.samples.enumerated()), id: \.offset) { _, sample in
                        LineMark(x: .value("Time", sample.time), y: .value("CPU (%)", sample.value * 100))
                    }
                    if let selection {
                        RectangleMark(xStart: .value("Start", selection.lowerBound), xEnd: .value("End", selection.upperBound))
                            .foregroundStyle(Color.accentColor.opacity(0.15))
                    }
                }
                .chartXSelection(range: $selection)
                .chartYScale(domain: 0...100)
                .chartYAxisLabel("Machine CPU (%)")
                .frame(height: 220)
                .accessibilityLabel("Machine CPU history; use the interval date controls to select evidence")
                if let selection {
                    DatePicker("Interval start", selection: Binding(get: { selection.lowerBound }, set: { self.selection = min($0, selection.upperBound)...selection.upperBound }), displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Interval end", selection: Binding(get: { selection.upperBound }, set: { self.selection = selection.lowerBound...max($0, selection.lowerBound) }), displayedComponents: [.date, .hourAndMinute])
                    Text("\(observations.count) retained process snapshots in \(selection.lowerBound.formatted()) – \(selection.upperBound.formatted()). Each retains the top 24 by CPU and memory; this is not a complete historical census.")
                        .font(ConsoleFont.caption)
                    if observations.isEmpty { Text("No process evidence was retained for this interval. Current processes cannot explain a past spike.") }
                    ForEach(observations) { observation in
                        DisclosureGroup(observation.time.formatted()) {
                            ForEach(observation.processes.filter {
                                console.search.isEmpty || $0.executable.localizedCaseInsensitiveContains(console.search) || String($0.pid).contains(console.search)
                            }, id: \.pid) { process in
                                HStack {
                                    Text("\(process.executable) · pid \(process.pid) · \(process.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "CPU unavailable")")
                                    Spacer()
                                    Button("Investigate") {
                                        model.investigate(InvestigationRequest(kind: "historical-process", subject: "pid \(process.pid)", observedAt: observation.time,
                                            values: [:], context: ["scope": "historical observation; do not treat PID as current", "attribution": "correlation only"], processes: [process]))
                                    }
                                }.font(ConsoleFont.caption)
                            }
                        }
                    }
                    let jobs = model.jobObservations.filter { selection.contains($0.time) }
                    Text("Agent/service observations: \(jobs.count) controller snapshots in this interval. Ownership and detected-session identity are evidence of association, not proof that a job caused a spike.").font(ConsoleFont.caption)
                    if jobs.isEmpty { Text("No agent-job evidence was retained for this interval.").font(ConsoleFont.caption) }
                    ForEach(jobs) { snapshot in
                        DisclosureGroup("Agents/services · " + snapshot.time.formatted()) {
                            ForEach(Array(snapshot.entries.enumerated()), id: \.offset) { _, entry in
                                Text(entry).font(ConsoleFont.caption)
                            }
                        }
                    }
                } else {
                    Button("Select latest 30 seconds") { selection = model.system.sampledAt.addingTimeInterval(-30)...model.system.sampledAt }
                    Text("Select an interval to inspect contemporaneous evidence.").font(ConsoleFont.caption)
                }
        }
        .padding(ConsoleMetrics.gutter)
    }
}

@Observable @MainActor
final class LaterTasks {
    struct Item: Identifiable, Codable { let id: UUID; var title: String; var complete: Bool }
    static let shared = LaterTasks()
    var items: [Item] {
        didSet { if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: "fleetconsole.laterTasks.v1") } }
    }
    private init() {
        items = UserDefaults.standard.data(forKey: "fleetconsole.laterTasks.v1")
            .flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? []
    }
}

struct LaterTasksView: View {
    @State private var title = ""
    @Bindable private var tasks = LaterTasks.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pending / Later").font(ConsoleFont.cardTitle)
            Text("Local reminders you add; these do not schedule or authorize agent work.").font(ConsoleFont.caption)
            HStack {
                TextField("Task to revisit", text: $title).onSubmit(add)
                Button("Add", action: add).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tasks.items.count >= 100)
            }
            if tasks.items.isEmpty { Text("No later tasks saved.").font(ConsoleFont.caption) }
            if tasks.items.contains(where: \.complete) {
                Button("Clear completed reminders") { tasks.items.removeAll(where: \.complete) }
            }
            ForEach($tasks.items) { $item in
                Toggle(item.title, isOn: $item.complete)
                    .toggleStyle(.checkbox)
            }
        }.elevatedCard()
    }
    private func add() {
        let value = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        guard !value.isEmpty, tasks.items.count < 100 else { return }
        tasks.items.append(.init(id: UUID(), title: value, complete: false)); title = ""
    }
}
