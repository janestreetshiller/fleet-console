import SwiftUI
import FleetCore

/// One live workspace: compact telemetry, accountable work, then the full
/// virtualized process table. It reuses AppModel's collectors and controller.
struct ConsolidatedConsole: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel

    var body: some View {
        GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 0) {
            ConsoleResourceStrip(model: model, columns: geometry.size.width >= ConsoleMetrics.cardMinWidth * 2 ? 4 : 2)
                .padding(.horizontal, ConsoleMetrics.gutter)
                .padding(.top, ConsoleMetrics.cardPadding)
                .padding(.bottom, ConsoleMetrics.cardPadding)
            Divider()
            ConsoleWorkSummary(model: model, console: console)
                .padding(.horizontal, ConsoleMetrics.gutter)
                .padding(.vertical, ConsoleMetrics.panelInset)
            Divider()
            ProcessModule(model: model, console: console, embedded: true)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("console.processes")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

}

private struct ConsoleWorkSummary: View {
    let model: AppModel
    @Bindable var console: ConsoleModel

    private var currentSnapshot: Bool {
        LiveDaemonReadiness.snapshot(connected: model.connected, hasDaemon: model.daemon != nil,
            ageSeconds: model.lastSnapshotReceivedUptime.map { ProcessInfo.processInfo.systemUptime - $0 })
    }

    var body: some View {
        // Only this small status surface observes the lease clock. The process
        // table and resource plots do not rebuild for one-second age updates.
        let _ = model.clockTick
        VStack(alignment: .leading, spacing: ConsoleMetrics.panelInset) {
            HStack(spacing: ConsoleMetrics.cardGap) {
                Label(model.connected ? "Controller connected" : "Controller offline",
                      systemImage: model.connected ? "checkmark.circle" : "bolt.horizontal.circle")
                    .foregroundStyle(model.connected ? SurfaceInk.secondary : StatusTone.bad.ink)
                if model.connected {
                    if !currentSnapshot {
                        Text("Awaiting current snapshot").foregroundStyle(SurfaceInk.secondary)
                    } else if model.attention.isEmpty {
                        Text("No findings").foregroundStyle(SurfaceInk.secondary)
                    } else {
                        Menu {
                            ForEach(model.attention) { item in
                                Button(item.title) { console.reveal(item, model: model) }
                            }
                        } label: {
                            Label("\(model.attention.count) findings", systemImage: "exclamationmark.triangle")
                        }
                        .foregroundStyle(model.criticalCount > 0 ? StatusTone.bad.ink : StatusTone.warn.ink)
                        .accessibilityIdentifier("console.findings")
                    }
                }
                Spacer(minLength: ConsoleMetrics.panelInset)
                Button(currentSnapshot ? "Services (\(model.activeServices.count))" : "Service details") { console.operationsSection = "Services"; console.open(.services) }
                    .help("Open service controls and retained logs")
                if model.awaitingReplyCount > 0 {
                    Button("\(model.awaitingReplyCount) awaiting reply") { console.operationsSection = "Agents"; console.open(.services) }
                }
            }
            .font(ConsoleFont.caption)
            .buttonStyle(.borderless)

            if !model.activeServices.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: ConsoleMetrics.cardGap) {
                        Text(currentSnapshot ? "Managed work" : "Last observed work")
                            .font(ConsoleFont.caption).foregroundStyle(SurfaceInk.secondary)
                        ForEach(model.activeServices) { row in
                            Button {
                                console.inspectConsoleService(row.id)
                            } label: {
                                HStack(spacing: ConsoleMetrics.panelInset) {
                                    Text(row.record.friendlyName).font(ConsoleFont.rowTitle.weight(.medium))
                                    Text(row.record.ownerAgent).foregroundStyle(SurfaceInk.secondary)
                                    Text(row.record.state.label).foregroundStyle(row.record.state.tone.ink)
                                }
                                .font(ConsoleFont.caption)
                                .padding(.vertical, ConsoleMetrics.panelInset)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(row.record.purpose)
                            .accessibilityIdentifier("console.service.\(row.id)")
                        }
                    }
                }
                .frame(height: ConsoleMetrics.workRowHeight)
                .scrollIndicators(.hidden)
            }

            if !model.sessions.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: ConsoleMetrics.cardGap) {
                        Text(currentSnapshot ? "Detected sessions" : "Last detected sessions")
                            .font(ConsoleFont.caption).foregroundStyle(SurfaceInk.secondary)
                        ForEach(model.sessions) { session in
                            Button {
                                console.inspectConsoleProcess(session.pid)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(session.tool).font(ConsoleFont.rowTitle.weight(.medium))
                                    Text("\(session.projectName) · pid \(session.pid)")
                                        .font(ConsoleFont.caption).foregroundStyle(SurfaceInk.secondary)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(model.processes.row(session.pid) == nil)
                            .help("Detected tool process; not proof of controller ownership")
                            .accessibilityIdentifier("console.session.\(session.id)")
                        }
                    }
                }
                .frame(height: ConsoleMetrics.workRowHeight)
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("console.work")
    }
}

/// Two short histories and two current readings, on the page rather than four
/// empty card shells. Charts use the existing time-aware observation series.
private struct ConsoleResourceStrip: View {
    let model: AppModel
    let columns: Int
    private var system: SystemMonitor { model.system }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: columns),
                  alignment: .leading, spacing: ConsoleMetrics.cardGap) {
            history(title: "CPU", value: system.cpu.sampled ? ConsoleFmt.utilPercent(system.cpu.usage) : "—",
                    detail: system.cpu.sampled ? "user \(ConsoleFmt.utilPercent(system.cpu.userShare)) · system \(ConsoleFmt.utilPercent(system.cpu.systemShare))" : "Waiting for two samples",
                    values: system.cpuHistory, times: system.cpuSeries.samples.map(\.time), metric: "CPU")
            history(title: "Memory", value: system.memory.totalBytes > 0 ? ConsoleFmt.utilPercent(system.memory.usedShare) : "—",
                    detail: system.memory.totalBytes > 0 ? "\(ConsoleFmt.bytes(system.memory.usedBytes)) · pressure \(system.memory.pressure.label)" : "Not available",
                    values: system.memoryHistory, times: system.memorySeries.samples.map(\.time), metric: "Memory")
            VStack(alignment: .leading, spacing: ConsoleMetrics.panelInset) {
                reading("Disk", value: system.storage.totalBytes > 0 ? ConsoleFmt.utilPercent(system.storage.usedShare) : "—",
                        detail: system.storage.totalBytes > 0 ? "\(ConsoleFmt.bytes(system.storage.availableBytes)) free" : "Not available")
                Button("Storage details") { consoleStorage() }
                    .font(ConsoleFont.caption).buttonStyle(.link)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: ConsoleMetrics.panelInset) {
                reading("Network", value: "↓ " + ConsoleFmt.byteRate(system.network.downloadBytesPerSec),
                        detail: "↑ " + ConsoleFmt.byteRate(system.network.uploadBytesPerSec))
                Text("Current transfer rate")
                    .font(ConsoleFont.micro).foregroundStyle(SurfaceInk.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("console.resources")
    }

    private func consoleStorage() {
        NotificationCenter.default.post(name: ConsoleCommand.selectModule, object: nil,
                                        userInfo: [ConsoleCommand.userInfoModule: ConsoleModule.storage.rawValue])
    }

    private func history(title: String, value: String, detail: String, values: [Double], times: [Date], metric: String) -> some View {
        VStack(alignment: .leading, spacing: ConsoleMetrics.panelInset) {
            reading(title, value: value, detail: detail)
            LoadWaveChart(values: values, times: times,
                          range: ChartTimeWindow.minutes2.range(endingAt: system.sampledAt),
                          height: ConsoleMetrics.chartAxisMinHeight, metric: metric)
                .accessibilityIdentifier("console.history.\(metric)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reading(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: ConsoleMetrics.panelInset) {
                Text(title).font(ConsoleFont.cardTitle).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text(value).font(ConsoleFont.cardValue).monospacedDigit().lineLimit(1)
            }
            Text(detail).font(ConsoleFont.micro).foregroundStyle(SurfaceInk.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
