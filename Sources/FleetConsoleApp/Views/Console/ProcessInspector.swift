import SwiftUI
import FleetCore
import Darwin

// Inspector: one process, deeply.
//
// Everything here is gathered the same way the rest of the app gathers facts:
// Mach/libproc for what the kernel will tell an unprivileged peer, `ps`/`lsof`
// for the rest. What macOS will not tell us — another user's environment, a
// root daemon's sockets — is labelled "not collected" rather than left blank,
// because a blank panel reads as a bug and a label reads as a policy.

/// The kernel's account of one process, via `proc_pidinfo(PROC_PIDTASKINFO)`.
/// Available for any process this user can see; thread *names* would need
/// `task_threads`, which the kernel quite reasonably refuses for other users'
// tasks.
struct TaskInfo: Equatable {
    var residentBytes: UInt64
    var virtualBytes: UInt64
    var userTimeNs: UInt64
    var systemTimeNs: UInt64
    var threadCount: Int32
    var runningThreads: Int32
    var priority: Int32
    var faults: Int32
    var pageIns: Int32

    static func read(pid: Int32) -> TaskInfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard written == size else { return nil }
        return TaskInfo(residentBytes: info.pti_resident_size,
                        virtualBytes: info.pti_virtual_size,
                        userTimeNs: info.pti_total_user,
                        systemTimeNs: info.pti_total_system,
                        threadCount: info.pti_threadnum,
                        runningThreads: info.pti_numrunning,
                        priority: info.pti_priority,
                        faults: info.pti_faults,
                        pageIns: info.pti_pageins)
    }
}

struct ProcessInspector: View {
    @Bindable var model: AppModel
    let pid: Int32

    @State private var taskInfo: TaskInfo?
    @State private var connections: [String] = []
    @State private var connectionsNote: String?
    @State private var sampling = false

    private var row: ProcessRow? { model.processes.row(pid) }

    /// The service that owns this pid, if the controller launched it.
    private var owningService: ServiceRecord? {
        model.activeServices.first { $0.record.pid == pid || $0.record.pgid == pid }?.record
            ?? model.activeServices.first { $0.record.pgid == row?.pgid }?.record
    }

    var body: some View {
        ScrollView {
            if let row {
                VStack(alignment: .leading, spacing: 14) {
                    header(row)
                    identityCard(row)
                    activityCard(row)
                    treeCard(row)
                    networkCard(row)
                    environmentCard
                    actionsCard(row)
                }
                .padding(14)
            } else {
                ContentUnavailableView("Process exited",
                                       systemImage: "rectangle.portrait.and.arrow.right",
                                       description: Text("pid \(pid) is no longer in the process table."))
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear { reload() }
        .onChange(of: pid) { reload() }
        .onChange(of: model.processes.capturedAt) { reloadTaskInfo() }
    }

    private func reload() {
        reloadTaskInfo()
        reloadConnections()
    }

    private func reloadTaskInfo() {
        let pid = self.pid
        DispatchQueue.global(qos: .utility).async {
            let info = TaskInfo.read(pid: pid)
            DispatchQueue.main.async { taskInfo = info }
        }
    }

    // MARK: Header

    private func header(_ row: ProcessRow) -> some View {
        InspectorHeader(symbol: Iconography.runtime(command: row.name,
                                                    commandLine: row.commandLine,
                                                    hasPorts: !row.ports.isEmpty),
                        tone: owningService != nil ? .good : .neutral,
                        title: row.displayName,
                        subtitle: "pid \(row.pid)",
                        subtitleKind: .identifier) {
            if let service = owningService {
                ConsoleBadge(text: service.friendlyName, tone: .good,
                             symbol: "checkmark.shield.fill")
            }
        }
    }

    // MARK: Identity

    private func identityCard(_ row: ProcessRow) -> some View {
        InspectorCard(title: "Identity") {
            InspectorLine(key: "PID", value: "\(row.pid)", mono: true)
            InspectorLine(key: "Parent", value: "\(row.ppid)", mono: true)
            InspectorLine(key: "Process group", value: "\(row.pgid)", mono: true)
            InspectorLine(key: "User", value: row.user, mono: true)
            InspectorLine(key: "Started", value: row.startSignature, mono: true)
            InspectorLine(key: "Command", value: row.commandLine, mono: true, wrap: true)
        }
    }

    // MARK: Activity

    private func activityCard(_ row: ProcessRow) -> some View {
        InspectorCard(title: "Activity") {
            InspectorLine(key: "CPU", value: ConsoleFmt.cpuPercent(row.cpuPercent), mono: true)
            InspectorLine(key: "Memory", value: ConsoleFmt.bytes(row.residentBytes), mono: true)
            if let taskInfo {
                InspectorLine(key: "Threads", value: "\(taskInfo.threadCount)"
                              + (taskInfo.runningThreads > 0 ? " (\(taskInfo.runningThreads) running)" : ""),
                              mono: true)
                InspectorLine(key: "Priority", value: "\(taskInfo.priority)", mono: true)
                InspectorLine(key: "CPU time", value: "\(ConsoleFmt.cpuTime(taskInfo.userTimeNs)) user · "
                              + "\(ConsoleFmt.cpuTime(taskInfo.systemTimeNs)) sys", mono: true)
                InspectorLine(key: "Virtual", value: ConsoleFmt.bytes(Int64(taskInfo.virtualBytes)), mono: true)
            } else {
                InspectorLine(key: "Threads", value: "not readable — the kernel declines "
                              + "task info for this process", mono: false)
            }
        }
    }

    // MARK: Tree

    private func treeCard(_ row: ProcessRow) -> some View {
        InspectorCard(title: "Process Tree") {
            let ancestry = model.processes.ancestry(of: row)
            // Root-most ancestor first: [grandparent, parent], depth = position.
            let lineage = Array(ancestry.reversed())
            ForEach(Array(lineage.indices), id: \.self) { index in
                treeLine(lineage[index], depth: index, isCurrent: false)
            }
            treeLine(row, depth: lineage.count, isCurrent: true)
            let children = (model.processes.childrenOf[row.pid] ?? [])
                .sorted { $0.residentBytes > $1.residentBytes }
            ForEach(children.prefix(12)) { child in
                treeLine(child, depth: ancestry.count + 1, isCurrent: false)
            }
            if children.count > 12 {
                Text("… and \(children.count - 12) more children")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
            }
        }
    }

    private func treeLine(_ row: ProcessRow, depth: Int, isCurrent: Bool) -> some View {
        Button { select(pid: row.pid) } label: {
            HStack(spacing: 6) {
                // Filled for you-are-here, hollow for the rest. Shapes rather than
                // ● / ○ glyphs, which sat on the text baseline and drifted with the
                // font's own metrics.
                Group {
                    if isCurrent {
                        Circle().fill(Color.accentColor)
                    } else {
                        Circle().strokeBorder(ConsoleColor.dim, lineWidth: 1)
                    }
                }
                .frame(width: ConsoleMetrics.treeMarker, height: ConsoleMetrics.treeMarker)
                Text(row.name)
                    .font(isCurrent ? ConsoleFont.subtitle.weight(.semibold) : ConsoleFont.subtitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text("\(row.pid)")
                    .font(ConsoleFont.mono(.caption2))
                    .foregroundStyle(SurfaceInk.secondary)
            }
            .padding(.leading, CGFloat(depth) * 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inspect \(row.name), process \(row.pid)")
        .accessibilityValue(isCurrent ? "Selected" : "")
    }

    private func select(pid: Int32) {
        NotificationCenter.default.post(name: .init("com.fleetconsole.console.selectPID"),
                                        object: nil, userInfo: ["pid": pid])
    }

    // MARK: Network

    private func networkCard(_ row: ProcessRow) -> some View {
        InspectorCard(title: "Network") {
            if row.ports.isEmpty {
                InspectorLine(key: "Listening", value: "none observed — lsof without root "
                              + "sees only this user's sockets", mono: false)
            } else {
                InspectorLine(key: "Listening", value: ConsoleFmt.ports(row.ports), mono: true)
            }
            if connections.isEmpty {
                InspectorLine(key: "Connections",
                              value: connectionsNote ?? "none established", mono: false)
            } else {
                ForEach(connections.prefix(8), id: \.self) { line in
                    Text(line)
                        .font(ConsoleFont.mono(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(line)
                }
                if connections.count > 8 {
                    Text("… \(connections.count - 8) more")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(SurfaceInk.secondary)
                }
            }
        }
    }

    private func reloadConnections() {
        guard let lsof = Shell.which("lsof", candidates: ["/usr/sbin/lsof", "/usr/bin/lsof"]) else {
            connectionsNote = "lsof not found"
            return
        }
        let pid = self.pid
        DispatchQueue.global(qos: .utility).async {
            let result = Shell.run(lsof, ["-nP", "-w", "-iTCP", "-a", "-p", "\(pid)"], timeout: 10)
            let lines = result.stdout.split(separator: "\n").map(String.init)
                .filter { $0.contains("TCP") }
                .compactMap { line -> String? in
                    let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                    guard fields.count >= 9 else { return nil }
                    return "\(fields[8]) \(fields.last ?? "")"
                }
            DispatchQueue.main.async {
                if result.succeeded {
                    connections = Array(Set(lines)).sorted()
                    connectionsNote = lines.isEmpty ? "none established" : nil
                } else {
                    connections = []
                    connectionsNote = "not readable for this process"
                }
            }
        }
    }

    // MARK: Environment

    @ViewBuilder
    private var environmentCard: some View {
        InspectorCard(title: "Environment") {
            if let service = owningService {
                if service.envKeys.isEmpty {
                    InspectorLine(key: "Extra keys", value: "none — launched with the controller's "
                                  + "scrubbed environment", mono: false)
                } else {
                    InspectorLine(key: "Extra keys", value: service.envKeys.sorted().joined(separator: "  "),
                                  mono: true)
                }
                Text("Keys only, never values (threat model T6): an environment that cannot leak "
                     + "a token cannot be screenshotted into one either.")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
            } else {
                InspectorLine(key: "Extra keys", value: "not collected — FleetConsole reads no "
                              + "environment from processes it does not manage", mono: false)
            }
        }
    }

    // MARK: Actions

    private func actionsCard(_ row: ProcessRow) -> some View {
        InspectorCard(title: "Actions") {
            if let service = owningService, let refusal = service.signalRefusal {
                // Claimed: supervised, reported on, and deliberately without a
                // single control. The sentence is the card's whole content, which
                // is the honest shape — there is nothing to press.
                Text(refusal)
                    .font(ConsoleFont.subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let service = owningService {
                VStack(alignment: .leading, spacing: 8) {
                    InspectorActionButton(title: "Stop…", symbol: "stop.fill", tone: .warn) {
                        model.stop(service)
                    }
                    InspectorActionButton(title: "Restart…", symbol: "arrow.clockwise", tone: .neutral) {
                        model.restart(service)
                    }
                    InspectorActionButton(title: service.state.isPaused ? "Resume" : "Pause",
                                          symbol: service.state.isPaused ? "play.fill" : "pause.fill",
                                          tone: .neutral) {
                        service.state.isPaused ? model.resume(service) : model.pause(service)
                    }
                }
                Text("Signalled through the controller — the PID-reuse guard and the audit event "
                     + "come with it.")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    InspectorActionButton(title: sampling ? "Sampling…" : "Sample",
                                          symbol: "waveform.path.ecg", tone: .neutral) {
                        sampling = true
                        ProcessActions.sample(row)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { sampling = false }
                    }
                    InspectorActionButton(title: "Copy PID", symbol: "doc.on.doc", tone: .neutral) {
                        ProcessActions.copy(ConsoleFmt.pid(row.pid))
                    }
                    InspectorActionButton(title: "Activity Monitor", symbol: "arrow.up.forward.app",
                                          tone: .neutral) {
                        model.openActivityMonitor()
                    }
                }
                Text("FleetConsole never signals a process it did not start — a recycled PID must "
                     + "never be hit. The verbs above are read-only.")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
            }
        }
    }
}

// MARK: - Shared inspector primitives

/// The block at the top of every inspector: what you are looking at, and the one
/// fact that qualifies it.
///
/// There were five of these, hand-built, and they had already drifted — two
/// spacings, three subtitle fonts, and a title that truncated in one and wrapped
/// in none. Same reason `FleetRowLabel` exists: the header is chrome, and chrome
/// belongs to one implementation.
struct InspectorHeader<Accessory: View>: View {
    /// How the qualifying line under the title is rendered. The distinction is
    /// semantic, not cosmetic — a state word is coloured by the tone, an
    /// identifier is monospaced because you will compare it character by
    /// character, and a quantity is the headline fact so it keeps its weight.
    enum Subtitle {
        case status
        case identifier
        case quantity
        case plain
    }

    let symbol: String
    var tone: StatusTone = .neutral
    let title: String
    var subtitle: String?
    var subtitleKind: Subtitle = .plain
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            EntityIcon(symbol: symbol, tone: tone, size: ConsoleMetrics.iconInspector)
            VStack(alignment: .leading, spacing: 2) {
                // Wraps rather than truncates: the name of the thing under
                // inspection is the one string on the panel that must survive a
                // narrow column intact.
                Text(title)
                    .font(ConsoleFont.cardTitle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    HStack(spacing: 6) {
                        Text(subtitle)
                            .font(subtitleFont)
                            .monospacedDigit()
                            .foregroundStyle(subtitleColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(subtitle)
                        accessory
                    }
                } else {
                    accessory
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitleFont: Font {
        switch subtitleKind {
        case .status, .plain: return ConsoleFont.caption
        case .identifier: return ConsoleFont.mono(.caption)
        case .quantity: return ConsoleFont.mono(.callout)
        }
    }

    private var subtitleColor: Color {
        switch subtitleKind {
        case .status: return tone.ink
        case .identifier, .quantity, .plain: return .secondary
        }
    }
}

extension InspectorHeader where Accessory == EmptyView {
    init(symbol: String, tone: StatusTone = .neutral, title: String,
         subtitle: String? = nil, subtitleKind: Subtitle = .plain) {
        self.init(symbol: symbol, tone: tone, title: title, subtitle: subtitle,
                  subtitleKind: subtitleKind) { EmptyView() }
    }
}

/// The inspector's card: one titled group of facts. Same elevation treatment
/// as content-column cards, tighter padding for the narrower column.
struct InspectorCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(ConsoleFont.subtitle.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard(padding: 12)
    }
}

/// One key/value line inside an inspector card.
struct InspectorLine: View {
    let key: String
    let value: String
    var mono = false
    var wrap = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(ConsoleFont.caption)
                .foregroundStyle(SurfaceInk.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(mono ? ConsoleFont.mono(.caption) : ConsoleFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(wrap ? nil : 1)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: wrap)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                // A single-line value in a 280pt column truncates, and a
                // truncated path or command is not a fact. Selectable already,
                // now also readable without selecting it.
                .help(value)
        }
    }
}

/// Compact bordered action used inside the actions card.
struct InspectorActionButton: View {
    let title: String
    let symbol: String
    var tone: StatusTone = .neutral
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(ConsoleFont.badge)
                Text(title)
                    .font(ConsoleFont.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: ConsoleMetrics.controlCorner, style: .continuous)
                    .fill(tone == .neutral ? AnyShapeStyle(.quaternary)
                                           : AnyShapeStyle(tone.chipFill))
            )
            .foregroundStyle(tone == .neutral ? ConsoleColor.numeral : tone.ink)
        }
        .buttonStyle(.plain)
    }
}
