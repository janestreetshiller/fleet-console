import SwiftUI
import FleetCore

struct ProcessesContent: View {
    @Bindable var model: AppModel
    var openDashboard: () -> Void

    @State private var pendingTermination: ProcessRow?
    @State private var refusal: String?
    @State private var weight: ProcessWeight = .cpu

    private var inventory: ProcessInventory { model.processes }
    private var terminationEnabled: Bool { model.settings.features.allowProcessTermination }

    private static let topCount = 5

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("Top \(min(Self.topCount, inventory.rows.count)) of \(inventory.rows.count)")
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

                Button("View all processes") {
                    openDashboard()
                    NotificationCenter.default.post(name: ConsoleCommand.selectModule, object: nil,
                        userInfo: [ConsoleCommand.userInfoModule: ConsoleModule.processes.rawValue])
                }
                .buttonStyle(.plain)
                .font(FleetFont.caption)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("processes.viewAll")
                .padding(.horizontal, FleetMetrics.gutter)
                .padding(.vertical, 8)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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
                    role: ProcessRole.describe(row, model: model),
                    weight: weight,
                    block: inventory.terminationBlock(for: row, enabled: terminationEnabled),
                    inspect: { inspect(row) },
                    end: { pendingTermination = row })
                .investigatable(.process(row, model: model), model: model)
            }
        }
    }

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

private struct ProcessPopoverRow: View {
    let row: ProcessRow
    let role: String?
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

            if row.state.tone != .neutral {
                Tag(text: row.state.label, tone: row.state.tone)
            }

            Text(usage)
                .font(FleetFont.mono(11))
                .monospacedDigit()
                .foregroundStyle(severity == .neutral ? FleetColor.numeral : severity.ink)
                .lineLimit(1)
                .fixedSize()

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
        .help("\(identity) — \(row.commandLine)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityActions {
            Button("Inspect in dashboard", action: inspect)
            if block == nil { Button("End process", action: end) }
        }
    }

    @ViewBuilder
    private var endButton: some View {
        if let block {
            IconButton(symbol: "xmark.circle", help: block.explanation) {}
                .disabled(true)
        } else {
            IconButton(symbol: "xmark.circle", help: "End this process (SIGTERM)", action: end)
        }
    }

    private var subtitle: String { role ?? identity }

    private var identity: String {
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

enum ProcessRole {
    @MainActor
    static func describe(_ row: ProcessRow, model: AppModel) -> String? {
        if let service = model.activeServices.first(where: { $0.record.pid == row.pid })?.record {
            return "Managed · \(service.purpose)"
        }
        if let session = model.sessions.first(where: { $0.pid == row.pid }) {
            return "\(session.tool) agent session" + (session.project.map { " · \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? "")
        }
        return describe(commandLine: row.commandLine, ports: row.ports, user: row.user)
    }

    static func describe(commandLine: String, ports: [Int], user: String) -> String? {
        if let range = commandLine.range(of: ".app/Contents/") {
            let app = URL(fileURLWithPath: String(commandLine[..<range.lowerBound])).lastPathComponent
            return ports.isEmpty ? "App · \(app)" : "App · \(app) · \(Fmt.ports(ports))"
        }
        if !ports.isEmpty { return "Server · \(Fmt.ports(ports))" }
        let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/"]
        if user == "root" || user.hasPrefix("_") || systemPrefixes.contains(where: commandLine.hasPrefix) {
            return "macOS system process"
        }
        return nil
    }
}
