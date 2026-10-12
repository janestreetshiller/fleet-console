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

    private enum Focus: String, CaseIterable { case both = "CPU & Memory", cpu = "CPU", memory = "Memory" }
    @State private var focus: Focus = .both
    @State private var timeWindow: ChartTimeWindow = .minutes2
    @State private var moreMetrics = false
    private var timeRange: ClosedRange<Date> { timeWindow.range(endingAt: system.sampledAt) }

    var body: some View {
        GeometryReader { geometry in
            let layout = OverviewViewportGeometry(viewport: geometry.size, focused: focus != .both,
                                                  instrumentCount: system.power.hasBattery ? 5 : 4,
                                                  verticalSafeArea: geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
            VStack(alignment: .leading, spacing: OverviewViewportGeometry.gap) {
                ModuleHeader(title: "Overview", subtitle: subtitle, symbol: ConsoleModule.overview.symbol)
                if layout.controlsStacked {
                    VStack(alignment: .leading, spacing: 8) { focusPicker; timePicker }
                } else {
                    HStack(spacing: 16) { focusPicker; Spacer(minLength: 8); timePicker }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: layout.primaryColumns),
                          spacing: OverviewViewportGeometry.gap) {
                    if focus != .memory { cpuCard(plotHeight: layout.plotHeight) }
                    if focus != .cpu { memoryCard(plotHeight: layout.plotHeight) }
                }
                OverviewMetricGlance(storage: system.storage, gpu: system.gpu, network: system.network,
                                     sensors: system.sensors, power: system.power, columns: layout.secondaryColumns) {
                    moreMetrics = true
                }
                processMapCard(limit: layout.processLimit)
                footer
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
            ModuleHeader(title: "System Metrics", subtitle: subtitle, symbol: "slider.horizontal.3") {
                Button("Done") { moreMetrics = false }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("overview.metrics.done")
            }
            timePicker
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: ConsoleMetrics.cardGap) {
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
    }

    private var focusPicker: some View {
        Picker("Chart focus", selection: $focus) {
            ForEach(Focus.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("overview.focus")
        .help("Give CPU or memory the full chart width")
    }

    private var historyStatus: String {
        guard let first = system.cpuSeries.samples.first?.time else { return "Collecting history…" }
        let seconds = Int(max(0, system.sampledAt.timeIntervalSince(first)))
        return seconds < timeWindow.rawValue - 2 ? "Live · \(seconds) s collected" : "Live"
    }

    private var timePicker: some View {
        HStack(spacing: 8) {
            Text(historyStatus).font(ConsoleFont.caption).foregroundStyle(.secondary)
            Picker("Time range", selection: $timeWindow) {
                ForEach(ChartTimeWindow.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("overview.time")
            .help("Zoom the visible time range without averaging samples")
        }
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
            subtitle: "pressure \(system.memory.pressure.label)"
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
    }

    // MARK: Process map

    private func processMapCard(limit: Int) -> some View {
        OverviewProcessPreview(rows: model.processes.rows, query: console.search, limit: limit, console: console)
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
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: Iconography.Metric.thermal)
                .font(ConsoleFont.caption)
                .foregroundStyle(SystemThresholds.thermal(system.thermal.state).ink)
            Text("Thermal state \(system.thermal.label)")
                .font(ConsoleFont.caption)
                .foregroundStyle(.secondary)
            // When the SMC is unlocked, the footer names what the band is
            // standing in for — a state plus its degrees and RPM is a claim
            // you can check against the card above.
            if model.license.isUnlocked(.smcSensors), system.sensors.available {
                Text("· \(SystemFmt.temperature(system.sensors.cpuTempC)) · \(SystemFmt.rpm(system.sensors.maxRPM))")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
            }
            Spacer()
            if let captured = model.processes.capturedAt {
                Text("process table \(Fmt.relative(captured))")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Process preview

/// Filter first, then cap a memory ranking. The complete table and inspector
/// keep their existing navigation paths instead of being duplicated here.
struct OverviewProcessPreview: View {
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
                Text("Memory").frame(width: 95, alignment: .trailing)
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
                    Divider()
                }
            }
            if matching.isEmpty {
                Text(query.trimmingCharacters(in: .whitespaces).isEmpty ? "Reading processes…" : "No matching processes.")
                    .font(ConsoleFont.body)
                    .foregroundStyle(SurfaceInk.secondary)
            }
            Text("Top \(limit) by resident memory · CPU is measured per core.")
                .font(ConsoleFont.caption)
                .foregroundStyle(SurfaceInk.secondary)
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
        .elevatedCard(padding: 8)
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
    }
}

// MARK: - Shared bits

/// App / Wired / Compressed / Swap, plus the total, laid out as a flow.
///
/// The row this replaces was an `HStack` of four `MemoryFact`s and a trailing
/// total, which needs about 380pt. In a grid cell it does not get 380pt, and an
/// HStack's answer to that is to compress every child at once: the badge labels
/// hyphenated and the total was pushed past the card's edge. `MemoryFact` already
/// pins its own width for exactly this reason, so what is left is to let the row
/// wrap — as many as fit, the rest on the next line, at any column count.
private struct MemoryFacts: View {
    let memory: MemorySample

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(spacing: 14)
            row(spacing: 10)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    MemoryFact(label: "App", value: memory.appBytes)
                    MemoryFact(label: "Wired", value: memory.wiredBytes)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    MemoryFact(label: "Compressed", value: memory.compressedBytes)
                    if memory.swapTotalBytes > 0 {
                        MemoryFact(label: "Swap", value: memory.swapUsedBytes)
                    }
                    Spacer(minLength: 0)
                }
                total
            }
        }
    }

    private func row(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            MemoryFact(label: "App", value: memory.appBytes)
            MemoryFact(label: "Wired", value: memory.wiredBytes)
            MemoryFact(label: "Compressed", value: memory.compressedBytes)
            if memory.swapTotalBytes > 0 {
                MemoryFact(label: "Swap", value: memory.swapUsedBytes)
            }
            Spacer(minLength: 4)
            total
        }
    }

    /// "13.3 GB of 17.18 GB" is the used figure the dial already reads as a
    /// percentage, in the units you act on.
    private var total: some View {
        Text("\(ConsoleFmt.bytes(memory.usedBytes)) of \(ConsoleFmt.bytes(memory.totalBytes))")
            .font(ConsoleFont.mono(.caption))
            .monospacedDigit()
            .foregroundStyle(SurfaceInk.secondary)
            .lineLimit(1)
            .fixedSize()
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
            Text(label.uppercased())
                .font(ConsoleFont.badge)
                .foregroundStyle(SurfaceInk.secondary)
                .kerning(0.5)
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

/// The heading row every module opens with — title2 per the window type ramp,
/// with the module's live subtitle and an optional trailing control.
///
/// Nothing here is allowed to wrap. The content column now shares its width
/// with the chrome tool panel, so this row has to survive being narrowed: the
/// title holds one line, and the subtitle gives up its space first and ends in
/// a tail ellipsis rather than pushing the trailing control off the row.
struct ModuleHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let symbol: String
    @ViewBuilder var trailing: Trailing

    init(title: String, subtitle: String? = nil, symbol: String,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.trailing = trailing()
    }

    /// The plate number this module carries — "MODULE 03 / 06" — taken from the
    /// picker's own order rather than typed, so a seventh module renumbers the
    /// set instead of leaving five headers lying about how many there are.
    /// Surfaces that are not modules (Home, a remote device's detail) have no
    /// number and say so by having none.
    private var eyebrow: String? {
        guard let module = ConsoleModule(rawValue: title) else { return nil }
        return String(format: "MODULE %02d / %02d",
                      module.shortcutIndex, ConsoleModule.allCases.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: symbol)
                    .font(ConsoleFont.cardTitle)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                // Sentence case at the module ramp's own size. The stamped
                // all-caps line this replaces was set in a bundled typewriter
                // face at a fixed 17pt — the one piece of text in the app that
                // ignored Dynamic Type, in the one position where a module
                // announces what you are looking at.
                Text(title)
                    .font(ConsoleFont.moduleTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let subtitle, subtitle.caseInsensitiveCompare(title) != .orderedSame {
                    Text(subtitle)
                        .font(ConsoleFont.mono(.caption))
                        .foregroundStyle(SurfaceInk.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                }
                Spacer(minLength: 4)
                trailing
            }
            Divider().padding(.top, 8)
        }
        .accessibilityElement(children: .contain)
    }
}
