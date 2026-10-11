import SwiftUI
import FleetCore

// Module: Overview — the live telemetry screen.
//
// Four instruments, each one a card: CPU (wave + per-core grid), memory
// (used share + pressure), disk I/O (read/write throughput), and GPU where the
// accelerator reports one. Numbers that move every two seconds are rendered
// with monospaced digits so the columns never jitter — the HIG rule for live
// data, applied everywhere without exception.
//
// The cards **flow** rather than stack. Every one of them was full width and
// full stop, so the module was as tall as the sum of its instruments however
// much width the window had: with the sidebar and inspector both open the
// content column is around 420pt and a card is a screenful, and with them both
// closed it is over 900pt and a card is a 900pt-wide chart of sixty samples
// beside 500pt of nothing. An adaptive grid spends width when there is width and
// falls back to one column when there is not, which is the same argument the
// chrome tool panel already makes about the terminal.
//
// The process map is the exception and stays full width: it is a treemap, its
// tiles are read as area, and halving its width does not halve the information —
// it makes the fortieth tile unclickable.

struct OverviewModule: View {
    @Bindable var model: AppModel
    /// Read for one reason: the toolbar's search field is present on this module
    /// and nothing here used to consume it. Typing a process name — the obvious
    /// thing to type while looking at a process map — filtered nothing and gave
    /// no sign it had done nothing, which reads as a frozen window rather than
    /// as a field that does not apply here.
    @Bindable var console: ConsoleModel

    private var system: SystemMonitor { model.system }

    /// Width of the content column, measured rather than assumed — the sidebar
    /// and the inspector both change it while the window stays the same size.
    @State private var contentWidth: CGFloat = 0

    private var instrumentCount: Int {
        5 + (system.gpu.available ? 1 : 0) + (system.power.hasBattery ? 1 : 0)
    }

    /// How many instruments sit on a row.
    ///
    /// A plain `.adaptive` grid takes every column the width allows, and at the
    /// width this module usually has that is three — which puts CPU, Memory and
    /// Disk on one row and leaves GPU alone beside two empty slots. The hole is
    /// the widest thing on the surface and it reads as a missing card. So the
    /// count steps down when the last row would hold exactly one of three or
    /// more: four cards become 2x2 rather than 3+1.
    private var instrumentColumns: Int {
        ConsoleLayout.telemetryColumns(contentWidth: contentWidth,
                                       instrumentCount: instrumentCount,
                                       minimumCardWidth: ConsoleMetrics.cardMinWidth,
                                       gap: ConsoleMetrics.cardGap)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ConsoleMetrics.cardGap) {
                ModuleHeader(
                    title: "Overview",
                    subtitle: subtitle,
                    symbol: ConsoleModule.overview.symbol)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(),
                                                            spacing: ConsoleMetrics.cardGap,
                                                            alignment: .top),
                                         count: instrumentColumns),
                          alignment: .leading,
                          spacing: ConsoleMetrics.cardGap) {
                    cpuCard
                    memoryCard
                    diskCard
                    if system.gpu.available { gpuCard }
                    networkCard
                    sensorCard
                    if system.power.hasBattery { powerCard }
                }
                .background(GeometryReader { proxy in
                    Color.clear.onAppear { contentWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, new in contentWidth = new }
                })

                processMapCard
                footer
            }
            .padding(ConsoleMetrics.gutter)

        }
        .scrollContentBackground(.hidden)
    }

    private var subtitle: String {
        var parts = [system.topology.brand]
        if !system.topology.coreSummary.isEmpty { parts.append(system.topology.coreSummary) }
        return parts.joined(separator: " · ")
    }

    // MARK: Sensors

    /// The SMC card: fan speed and die temperature from the hardware, not from
    /// `thermalState`'s four bands.
    ///
    /// The card is premium-gated, and the three states it renders are three
    /// different sentences on purpose:
    ///   * locked — what the feature *is*, so the paywall advertises honestly;
    ///   * available but no keys — the SMC answered and held nothing (the
    ///     normal Apple silicon answer), said as "no keys", not as zeros;
    ///   * unavailable — no SMC at all (VMs, very old Macs).
    /// A fourth state — a licensed machine reporting a number — needs no
    /// prose; the number is the sentence.
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

    private var cpuCard: some View {
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
            // The standard trace height, not the tall one. The card is a grid cell
            // now, and a CPU chart 32pt taller than its three neighbours sets the
            // height of the whole row it lands in.
            LoadWaveChart(values: system.cpuHistory,
                          tint: cpuTint,
                          height: ConsoleMetrics.chartHeight)
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
    }

    private var cpuTint: Color {
        .accentColor
    }

    // MARK: Memory

    private var memoryCard: some View {
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
                          tint: .accentColor,
                          height: ConsoleMetrics.chartHeight)
            // Wrapped rather than laid out in one row of five. At a grid cell's
            // width the old row hyphenated "COMPRESSED" and then pushed the total
            // off the card; a flow lays out as many as fit and moves the rest down
            // one line, which is the same answer at any column count.
            MemoryFacts(memory: system.memory)
        }
    }

    // MARK: Process map

    /// The map's rows, filtered the same way `ProcessModule` filters its table —
    /// name or command line, case-insensitive — so one query means one thing
    /// across both surfaces.
    private var mapRows: [ProcessRow] {
        let query = console.search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.processes.rows }
        return model.processes.rows.filter { row in
            row.name.localizedCaseInsensitiveContains(query)
                || row.commandLine.localizedCaseInsensitiveContains(query)
        }
    }

    private var processMapCard: some View {
        let rows = mapRows.sorted { $0.residentBytes > $1.residentBytes }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Processes").font(ConsoleFont.cardTitle)
                Spacer()
                Button("View All") { console.open(.processes) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("View all processes")
            }
            HStack {
                Text("Process")
                Spacer()
                Text("CPU").frame(width: 70, alignment: .trailing)
                Text("Memory").frame(width: 95, alignment: .trailing)
            }
            .font(ConsoleFont.caption)
            .foregroundStyle(SurfaceInk.secondary)
            ForEach(rows.prefix(5)) { row in
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
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight()
                .accessibilityLabel("Inspect \(row.displayName), CPU \(ConsoleFmt.cpuPercent(row.cpuPercent)), memory \(ConsoleFmt.bytes(row.residentBytes))")
                Divider()
            }
            if rows.isEmpty {
                Text(console.search.isEmpty ? "Reading processes…" : "No matching processes.")
                    .font(ConsoleFont.body)
                    .foregroundStyle(SurfaceInk.secondary)
            }
            Text("Largest by resident memory. Process CPU is measured per core.")
                .font(ConsoleFont.caption)
                .foregroundStyle(SurfaceInk.secondary)
        }
        .elevatedCard()
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
                            height: ConsoleMetrics.chartHeight)
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
                          tint: system.gpu.utilization.map { SystemThresholds.utilization($0).color }
                                ?? .accentColor,
                          height: ConsoleMetrics.chartHeight)
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
