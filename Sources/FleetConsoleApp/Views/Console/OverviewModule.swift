import SwiftUI
import FleetCore

// CPU and memory are the primary instruments. Time zoom preserves individual
// observations; focusing one metric gives it the full width and a taller plot.
// Secondary instruments have a glance and a sheet, never an expanding main page.
struct OverviewModule: View {
    @Bindable var model: AppModel
    /// Read for one reason: the toolbar's search field is present on this module
    /// and nothing here used to consume it. Typing a process name — the obvious
    /// thing to type while looking at a process map — filtered nothing and gave
    /// no sign it had done nothing, which reads as a frozen window rather than
    /// as a field that does not apply here.
    @Bindable var console: ConsoleModel

    private var system: SystemMonitor { model.system }

    @State private var moreMetrics = false
    private var focus: ConsoleModel.OverviewFocus { console.overviewFocus }
    private var timeWindow: ChartTimeWindow { console.overviewTimeWindow }
    private var timeRange: ClosedRange<Date> { console.overviewTimeWindow.range(endingAt: system.sampledAt) }

    var body: some View {
        GeometryReader { geometry in
            // `geometry.size` is already the unobscured module column: the
            // toolbar's safe area is outside it, so nothing is subtracted twice.
            let layout = OverviewViewportGeometry(viewport: geometry.size, focused: focus != .both,
                                                  instrumentCount: system.power.hasBattery ? 5 : 4)
            VStack(alignment: .leading, spacing: OverviewViewportGeometry.gap) {
                WorkspaceHeading(title: "Overview", detail: subtitle)
                    .frame(height: OverviewViewportGeometry.headingHeight, alignment: .topLeading)
                QuantizedCardGrid(
                    minimumCellWidth: (layout.contentWidth - CGFloat(layout.primaryColumns - 1) * OverviewViewportGeometry.gap) / CGFloat(layout.primaryColumns),
                    maximumColumns: layout.primaryColumns,
                    horizontalSpacing: OverviewViewportGeometry.gap,
                    verticalSpacing: OverviewViewportGeometry.gap) {
                    if focus != .memory { cpuCard(plotHeight: layout.plotHeight) }
                    if focus != .cpu { memoryCard(plotHeight: layout.plotHeight) }
                }
                OverviewMetricGlance(model: model, storage: system.storage, gpu: system.gpu, network: system.network,
                                     sensors: system.sensors, power: system.power, columns: layout.secondaryColumns) {
                    moreMetrics = true
                }
                processMapCard(limit: layout.processLimit)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: layout.contentWidth)
            .padding(.vertical, OverviewViewportGeometry.verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .sheet(isPresented: $moreMetrics) { detailedMetrics }
    }

    /// Detailed instruments have their own scrollable surface. Opening them must
    /// not move the primary traces or push the process actions below the window.
    private var detailedMetrics: some View {
        VStack(alignment: .leading, spacing: ConsoleMetrics.cardGap) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("System Metrics")
                    .font(ConsoleFont.cardTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Done") { moreMetrics = false }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("overview.metrics.done")
            }
            .accessibilityElement(children: .contain)
            timePicker
            ScrollView {
                QuantizedCardGrid(minimumCellWidth: 320, maximumColumns: 2) {
                    diskCard
                    if system.gpu.available {
                        gpuCard
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("GPU").font(ConsoleFont.cardTitle)
                            Text("GPU metrics aren’t available on this Mac.")
                                .font(ConsoleFont.body).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
                        .elevatedCard()
                    }
                    networkCard
                    sensorCard
                    if system.power.hasBattery { powerCard }
                }
                .padding(.bottom, ConsoleMetrics.cardGap)
            }
            .scrollContentBackground(.hidden)
        }
        .padding(ConsoleMetrics.gutter)
        .frame(width: 760, height: 620)
        .accessibilityIdentifier("overview.metrics.sheet")
        .actionErrorAlert(model: model)
    }

    private var timePicker: some View {
        Picker("Time range", selection: $console.overviewTimeWindow) {
            ForEach(ChartTimeWindow.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("overview.time")
        .help("Zoom the visible time range without averaging samples")
    }

    private var subtitle: String {
        var parts = [system.topology.brand]
        if !system.topology.coreSummary.isEmpty { parts.append(system.topology.coreSummary) }
        return parts.joined(separator: " · ")
    }

    // MARK: Sensors

    private var sensorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Sensors")
                    .font(ConsoleFont.cardTitle)
                Spacer()
                if !system.sensors.fans.isEmpty {
                    Text("\(system.sensors.fans.count) fan\(system.sensors.fans.count == 1 ? "" : "s")")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !system.sensors.fans.isEmpty || system.sensors.cpuTempC != nil
                || system.sensors.gpuTempC != nil {
                HStack(spacing: 16) {
                    sensorMetric(title: "Fan",
                                 value: SystemFmt.rpm(system.sensors.maxRPM),
                                 caption: system.sensors.fans.count > 1
                                    ? "fastest of \(system.sensors.fans.count)" : "actual speed")
                    sensorMetric(title: "CPU die",
                                 value: SystemFmt.temperature(system.sensors.cpuTempC),
                                 caption: "temperature")
                    sensorMetric(title: "GPU",
                                 value: SystemFmt.temperature(system.sensors.gpuTempC),
                                 caption: system.sensors.gpuTempC == nil
                                    ? "not reported" : "temperature")
                }
            } else {
                Text("Temperature and fan speed aren’t available on this Mac.")
                    .font(ConsoleFont.body)
                    .foregroundStyle(.secondary)
            }
            Text("Thermal state · \(system.thermal.label)")
                .font(ConsoleFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .elevatedCard("SMC · SENSORS")
        .investigatable(.metric("sensors", model: model), model: model)
    }

    private func sensorMetric(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(ConsoleFont.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(ConsoleFont.cardValue)
            Text(caption)
                .font(ConsoleFont.micro)
                .foregroundStyle(SurfaceInk.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: CPU

    private func cpuCard(plotHeight: CGFloat) -> some View {
        TelemetryCard(
            title: "CPU",
            plate: "01 · CPU",
            tone: system.cpu.sampled ? SystemThresholds.utilization(system.cpu.usage) : .unknown,
            value: system.cpu.sampled ? ConsoleFmt.utilPercent(system.cpu.usage) : "—",
            // Nil until two tick samples have been differenced, which parks the
            // needle instead of resting it on a confident zero.
            gaugeValue: system.cpu.sampled ? system.cpu.usage : nil,
            subtitle: system.cpu.sampled
                ? "user \(ConsoleFmt.utilPercent(system.cpu.userShare)) · sys \(ConsoleFmt.utilPercent(system.cpu.systemShare))"
                : "sampling…"
        ) {
            LoadWaveChart(values: system.cpuHistory,
                          times: system.cpuSeries.samples.map(\.time), range: timeRange,
                          tint: cpuTint,
                          height: plotHeight, metric: "CPU")
            HStack(alignment: .bottom) {
                CoreGrid(values: system.cpu.perCore, topology: system.topology)
                Spacer(minLength: 4)
                if !system.cpu.loadAverage.isEmpty {
                    Text("load \(ConsoleFmt.load(system.cpu.loadAverage))")
                        .font(ConsoleFont.mono(.caption))
                        .monospacedDigit()
                        .foregroundStyle(SurfaceInk.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                }
            }
        }
        .accessibilityIdentifier("overview.cpu")
        .investigatable(.metric("cpu", model: model), model: model)
    }

    private var cpuTint: Color {
        .accentColor
    }

    // MARK: Memory

    private func memoryCard(plotHeight: CGFloat) -> some View {
        TelemetryCard(
            title: "Memory",
            plate: "02 · MEM",
            tone: SystemThresholds.memory(system.memory),
            value: ConsoleFmt.utilPercent(system.memory.usedShare),
            // Always sampled: a share of physical memory is a ratio of two
            // absolute numbers, not a rate, so it needs no previous tick.
            gaugeValue: system.memory.usedShare,
            // The used figure in the units you act on sits with the pressure,
            // so the facts under the trace stay one row wide or two rows tall.
            subtitle: "pressure \(system.memory.pressure.label) · "
                + "\(ConsoleFmt.bytes(system.memory.usedBytes)) of \(ConsoleFmt.bytes(system.memory.totalBytes))"
        ) {
            LoadWaveChart(values: system.memoryHistory,
                          times: system.memorySeries.samples.map(\.time), range: timeRange,
                          tint: .accentColor,
                          height: plotHeight, metric: "Memory")
            // Wrapped rather than laid out in one row of five. At a grid cell's
            // width the old row hyphenated "COMPRESSED" and then pushed the total
            // off the card; a flow lays out as many as fit and moves the rest down
            // one line, which is the same answer at any column count.
            MemoryFacts(memory: system.memory)
        }
        .accessibilityIdentifier("overview.memory")
        .investigatable(.metric("memory", model: model), model: model)
    }

    // MARK: Process map

    private func processMapCard(limit: Int) -> some View {
        OverviewProcessPreview(model: model, rows: model.processes.rows, query: console.search, limit: limit, console: console)
    }

    // MARK: Disk

    private var diskCard: some View {
        TelemetryCard(
            title: "Disk",
            plate: "03 · I/O",
            // Was `.neutral`, because throughput has no good or bad value. The
            // dial reads capacity, which does — and it gets the early-warning
            // band, since by the time a volume is 99% full macOS is failing
            // writes rather than warning about them.
            tone: system.storage.totalBytes > 0
                ? SystemThresholds.freeSpace(share: system.storage.usedShare)
                : .unknown,
            value: ConsoleFmt.utilPercent(system.storage.usedShare),
            // The dial reads **capacity**, not throughput, and that is the one
            // place the gauge and the card's trace show different quantities. It
            // is deliberate: a needle needs a bounded scale, and byte rates are
            // the genuinely unbounded series in this app — the reason the chart
            // below it is the only logarithmic one. A dial whose full deflection
            // meant "the fastest rate seen so far this session" would be a scale
            // that silently rewrites itself, which is the failure the throughput
            // chart's fixed floor already exists to avoid. Used space is bounded,
            // it has a real redline, and it is the disk fact worth a glance.
            gaugeValue: system.storage.totalBytes > 0 ? system.storage.usedShare : nil,
            subtitle: system.storage.device
        ) {
            ThroughputChart(read: system.diskReadHistory,
                            write: system.diskWriteHistory,
                            times: system.diskReadSeries.samples.map(\.time), range: timeRange,
                            height: ConsoleMetrics.chartSecondaryHeight)
            HStack(spacing: 10) {
                LegendDot(label: TelemetrySeries.read.label,
                          value: ConsoleFmt.byteRate(system.storage.readBytesPerSec),
                          color: TelemetrySeries.read.color)
                LegendDot(label: TelemetrySeries.write.label,
                          value: ConsoleFmt.byteRate(system.storage.writeBytesPerSec),
                          color: TelemetrySeries.write.color)
                Spacer(minLength: 4)
            }
            Text("\(ConsoleFmt.bytes(system.storage.availableBytes)) available of \(ConsoleFmt.bytes(system.storage.totalBytes))")
                .font(ConsoleFont.mono(.caption))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .investigatable(.metric("disk", model: model), model: model)
    }

    // MARK: GPU

    private var gpuCard: some View {
        TelemetryCard(
            title: "GPU",
            plate: "04 · GPU",
            tone: system.gpu.utilization.map { SystemThresholds.utilization($0) } ?? .unknown,
            value: ConsoleFmt.utilPercent(system.gpu.utilization),
            // Nil when the accelerator is present but withheld the key — the
            // honest reading is "not reported", never an idle GPU.
            gaugeValue: system.gpu.utilization,
            subtitle: system.gpu.model
        ) {
            LoadWaveChart(values: system.gpuHistory,
                          times: system.gpuSeries.samples.map(\.time), range: timeRange,
                          tint: system.gpu.utilization.map { SystemThresholds.utilization($0).color }
                                ?? .accentColor,
                          height: ConsoleMetrics.chartSecondaryHeight, metric: "GPU")
            if let used = system.gpu.inUseMemoryBytes {
                HStack {
                    MemoryFact(label: "In use", value: used)
                    Spacer()
                }
            }
        }
        .investigatable(.metric("gpu", model: model), model: model)
    }

    // MARK: Network and power

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Network").font(ConsoleFont.cardTitle)
                Spacer(minLength: 4)
                Text(system.network.interfaceNames.isEmpty
                     ? "No active physical link" : system.network.interfaceNames.joined(separator: " · "))
                    .font(ConsoleFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ThroughputChart(read: system.networkDownloadHistory,
                            write: system.networkUploadHistory,
                            times: system.networkDownloadSeries.samples.map(\.time), range: timeRange,
                            readLabel: "Download", writeLabel: "Upload", metric: "Network")
            HStack(spacing: 13) {
                rateMetric("Download", rate: system.network.downloadBytesPerSec)
                Spacer(minLength: 0)
                rateMetric("Upload", rate: system.network.uploadBytesPerSec)
            }
            Text("Physical interfaces · VPN traffic not counted twice")
                .font(ConsoleFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .elevatedCard("NET · TRAFFIC")
        .investigatable(.metric("network", model: model), model: model)
    }

    private func rateMetric(_ label: String, rate: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(ConsoleFont.caption).foregroundStyle(.secondary)
            Text(ConsoleFmt.byteRate(rate))
                .font(ConsoleFont.mono(.body))
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var powerCard: some View {
        TelemetryCard(title: "Battery", plate: "PWR · BATTERY",
                      value: ConsoleFmt.utilPercent(system.power.chargeFraction),
                      gaugeValue: system.power.chargeFraction,
                      subtitle: system.power.isCharging ? "Charging"
                          : system.power.isPluggedIn ? "Connected to power" : "On battery") {
            if let charge = system.power.chargeFraction {
                ProgressView(value: charge).tint(SketchInk.accent)
            }
            if let minutes = system.power.minutesRemaining {
                Text("\(minutes) min \(system.power.isCharging ? "until full" : "remaining")")
                    .font(ConsoleFont.body).monospacedDigit()
            } else {
                Text("Time estimate not reported")
                    .font(ConsoleFont.caption).foregroundStyle(.secondary)
            }
        }
        .investigatable(.metric("battery", model: model), model: model)
    }

}

// MARK: - Process preview

/// Filter first, then cap a memory ranking. The complete table and inspector
/// keep their existing navigation paths instead of being duplicated here.
struct OverviewProcessPreview: View {
    let model: AppModel
    let rows: [ProcessRow]
    let query: String
    let limit: Int
    @Bindable var console: ConsoleModel

    private var matches: [ProcessRow] {
        let search = query.trimmingCharacters(in: .whitespaces)
        return rows.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
            || $0.commandLine.localizedCaseInsensitiveContains(search) }
            .sorted { $0.residentBytes > $1.residentBytes }
    }

    var body: some View {
        let matching = matches
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Top Processes").font(ConsoleFont.cardTitle)
                Text("\(min(limit, matching.count)) of \(matching.count)")
                    .font(ConsoleFont.caption).foregroundStyle(SurfaceInk.secondary)
                Spacer()
                Button("View All") { console.open(.processes) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("View all processes")
                    .accessibilityIdentifier("overview.processes.all")
            }
            HStack {
                Text("Process")
                Spacer()
                Text("CPU").frame(width: 70, alignment: .trailing)
                // The ranking key, marked where the eye reads the column.
                HStack(spacing: 3) {
                    Text("Memory")
                    Image(systemName: "chevron.down").font(ConsoleFont.marker)
                }
                .frame(width: 95, alignment: .trailing)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Memory, sorted descending")
            }
            .font(ConsoleFont.caption)
            .foregroundStyle(SurfaceInk.secondary)
            ForEach(matching.prefix(limit)) { row in
                VStack(spacing: 0) {
                    Button {
                        console.open(.processes)
                        console.selectedPID = row.pid
                    } label: {
                        HStack {
                            ProcessNameCell(row: row, managed: false)
                            Spacer(minLength: 8)
                            Text(ConsoleFmt.cpuPercent(row.cpuPercent))
                                .frame(width: 70, alignment: .trailing)
                            Text(ConsoleFmt.bytes(row.residentBytes))
                                .frame(width: 95, alignment: .trailing)
                        }
                        .font(ConsoleFont.body)
                        .monospacedDigit()
                        .frame(height: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                    .accessibilityLabel("Inspect \(row.displayName), CPU \(ConsoleFmt.cpuPercent(row.cpuPercent)), memory \(ConsoleFmt.bytes(row.residentBytes))")
                    .accessibilityIdentifier("overview.process.\(row.pid)")
                    .investigatable(.process(row, model: model), model: model)
                    Divider()
                }
            }
            if matching.isEmpty {
                Text(query.trimmingCharacters(in: .whitespaces).isEmpty ? "Reading processes…" : "No matching processes.")
                    .font(ConsoleFont.body)
                    .foregroundStyle(SurfaceInk.secondary)
            }
        }
        .elevatedCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.processes")
    }
}

// MARK: - Secondary glance

/// Small current readings remain on Overview; their full charts and hardware
/// facts belong to the adjacent Details action. Absence is never an idle zero.
struct OverviewMetricGlance: View {
    let model: AppModel
    let storage: StorageSample
    let gpu: GPUSample
    let network: NetworkTrafficSample
    let sensors: SensorSample
    let power: PowerSample
    var columns: Int = 4
    let showDetails: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: columns),
                      alignment: .leading, spacing: OverviewViewportGeometry.gap) {
                metric("Disk", value: storage.totalBytes > 0 ? ConsoleFmt.utilPercent(storage.usedShare) + " used" : "—",
                       detail: storage.totalBytes > 0 ? ConsoleFmt.bytes(storage.availableBytes) + " free" : "Not available", id: "disk")
                metric("GPU", value: ConsoleFmt.utilPercent(gpu.utilization),
                       detail: gpu.available ? (gpu.utilization == nil ? "Not reported" : gpu.model ?? "Utilization") : "Not available", id: "gpu")
                metric("Network", value: "↓ " + ConsoleFmt.byteRate(network.downloadBytesPerSec),
                       detail: "↑ " + ConsoleFmt.byteRate(network.uploadBytesPerSec), id: "network")
                    .help(network.interfaceNames.isEmpty ? "No active physical link" : network.interfaceNames.joined(separator: " · "))
                metric("Sensors", value: SystemFmt.temperature(sensors.cpuTempC),
                       detail: sensors.maxRPM.map { SystemFmt.rpm($0) } ?? "Fan not reported", id: "sensors")
                if power.hasBattery {
                    metric("Battery", value: ConsoleFmt.utilPercent(power.chargeFraction),
                           detail: power.isCharging ? "Charging" : power.isPluggedIn ? "On power" : "On battery", id: "battery")
                }
            }
            .frame(maxWidth: .infinity)
            Button("Details", action: showDetails)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Show detailed metrics")
                .accessibilityIdentifier("overview.metrics.details")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.glance")
    }

    private func metric(_ title: String, value: String, detail: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(ConsoleFont.caption).foregroundStyle(SurfaceInk.secondary)
            Text(value).font(ConsoleFont.mono(.body)).monospacedDigit()
            Text(detail).font(ConsoleFont.micro).foregroundStyle(SurfaceInk.secondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help("\(title): \(value) · \(detail)")
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("overview.glance.\(id)")
        .investigatable(.metric(id, model: model), model: model)
    }
}

// MARK: - Shared bits

/// App / Wired / Compressed / Swap: one row where it fits, two rows of two where
/// it does not — never three, which made the memory card set its row's height
/// and left the CPU card beside it with a band of nothing under its cores.
private struct MemoryFacts: View {
    let memory: MemorySample

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { first; second; Spacer(minLength: 0) }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow { first }
                GridRow { second }
            }
        }
    }

    @ViewBuilder private var first: some View {
        MemoryFact(label: "App", value: memory.appBytes)
        MemoryFact(label: "Wired", value: memory.wiredBytes)
    }

    @ViewBuilder private var second: some View {
        MemoryFact(label: "Compressed", value: memory.compressedBytes)
        if memory.swapTotalBytes > 0 {
            MemoryFact(label: "Swap", value: memory.swapUsedBytes)
        }
    }
}

private struct MemoryFact: View {
    let label: String
    let value: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // A four-column row of these divides the card evenly, which gives
            // "COMPRESSED" less width than it needs at the kerned badge size —
            // and SwiftUI's default response is to hyphenate, so the card read
            // "COM-PRESSED" stacked over its number. A label that is one word is
            // one line: it holds its intrinsic width and the row distributes
            // what is left, rather than the longest label being broken to keep
            // four columns nominally equal.
            Text(label)
                .font(ConsoleFont.badge)
                .foregroundStyle(SurfaceInk.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(ConsoleFmt.bytes(value))
                .font(ConsoleFont.mono(.caption))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// The row a module opens with when it has controls, and only then.
///
/// No title, no subtitle, no symbol. The sidebar's selection already names the
/// page, so a heading restating it was a second toolbar spending the height the
/// content needs. What is left is what the row is for: the controls that change
/// the page, leading and trailing, on one line that never wraps.
struct ModuleControlBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    init(@ViewBuilder leading: () -> Leading = { EmptyView() },
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leading
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 24)
        .accessibilityElement(children: .contain)
    }
}
