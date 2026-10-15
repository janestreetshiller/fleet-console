import SwiftUI
import FleetCore

struct QuickViewDial {
    let value: Double?
    let tone: StatusTone
    var readout: String { ConsoleFmt.utilPercent(value) }
}

@MainActor
struct QuickViewMetrics {
    let cpu: QuickViewDial
    let memory: QuickViewDial
    let disk: QuickViewDial
    static let diskCellCount = 20
    var diskFilledCells: Int {
        disk.value.map { Int(($0 * Double(Self.diskCellCount)).rounded()) } ?? 0
    }

    init(cpu: CPUSample, memory: MemorySample, storage: StorageSample = StorageSample()) {
        let cpuValue = cpu.sampled ? Self.validShare(cpu.usage) : nil
        let memoryValue = memory.totalBytes > 0 ? Self.validShare(memory.usedShare) : nil
        let diskValue = storage.totalBytes > 0 && storage.availableBytes >= 0
            && storage.availableBytes <= storage.totalBytes ? Self.validShare(storage.usedShare) : nil
        self.cpu = QuickViewDial(value: cpuValue,
                                 tone: cpuValue.map(SystemThresholds.utilization) ?? .unknown)
        self.memory = QuickViewDial(value: memoryValue,
                                    tone: memoryValue == nil ? .unknown : SystemThresholds.memory(memory))
        self.disk = QuickViewDial(value: diskValue,
                                  tone: diskValue.map { SystemThresholds.freeSpace(share: $0) } ?? .unknown)
    }

    private static func validShare(_ value: Double) -> Double? {
        value.isFinite && (0...1).contains(value) ? value : nil
    }
}

/// A fixed logarithmic scale, not a percentage of a guessed link speed.
struct QuickViewRate {
    let bytesPerSecond: Double?
    init(bytesPerSecond: Double?) {
        self.bytesPerSecond = bytesPerSecond.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
    var fraction: Double? {
        bytesPerSecond.map { min(1, log1p($0) / log1p(1_000_000_000)) }
    }
    var readout: String { ConsoleFmt.byteRate(bytesPerSecond) }
}

/// Four instruments sharing the existing probes. No extra collectors or timers.
struct QuickView: View {
    @Bindable var model: AppModel
    private static let instrumentSize: CGFloat = 90

    var body: some View {
        let metrics = QuickViewMetrics(cpu: model.system.cpu, memory: model.system.memory,
                                       storage: model.system.storage)
        HStack(alignment: .top, spacing: 10) {
            instrument("CPU") {
                RetroGauge(value: metrics.cpu.value, tone: metrics.cpu.tone, caption: "CPU",
                           readout: metrics.cpu.readout, diameter: Self.instrumentSize)
            }
            .help(model.system.topology.brand + " · " + model.system.topology.coreSummary)
            instrument("Memory") {
                RetroGauge(value: metrics.memory.value, tone: metrics.memory.tone, caption: "Memory",
                           readout: metrics.memory.readout, diameter: Self.instrumentSize)
            }
            .help("\(ConsoleFmt.bytes(model.system.memory.usedBytes)) used · pressure \(model.system.memory.pressure.label)")
            instrument("Disk") { disk(metrics) }
            instrument("Network") { network }
        }
        .padding(.horizontal, FleetMetrics.gutter)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
    }

    private func instrument<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(title)
                    .font(FleetFont.sectionLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                AgentHookButton(title: title) {
                    model.investigate(.metric(title.lowercased(), model: model))
                }
            }
            content().frame(height: Self.instrumentSize)
        }
        .frame(maxWidth: .infinity)
        .contextMenu {
            Button("Investigate \(title) with agent") {
                model.investigate(.metric(title.lowercased(), model: model))
            }
        }
    }

    private func disk(_ metrics: QuickViewMetrics) -> some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 5), spacing: 3) {
                ForEach(0..<QuickViewMetrics.diskCellCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: FleetMetrics.barCorner)
                        .fill(index < metrics.diskFilledCells
                              ? SystemThresholds.freeSpace(share: Double(index + 1) / Double(QuickViewMetrics.diskCellCount)).color
                              : FleetColor.indicatorOff)
                        .frame(height: 12)
                }
            }
            Text(metrics.disk.readout).font(FleetFont.mono(12, weight: .medium)).monospacedDigit()
        }
        .frame(width: Self.instrumentSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Disk storage")
        .accessibilityValue(metrics.disk.value == nil ? "Unavailable" : "\(metrics.disk.readout) used")
        .help(metrics.disk.value == nil ? "Disk capacity unavailable"
              : "\(ConsoleFmt.bytes(model.system.storage.availableBytes)) available of \(ConsoleFmt.bytes(model.system.storage.totalBytes)) · capacity, not temperature")
    }

    private var network: some View {
        VStack(spacing: 12) {
            rate("Download", symbol: "arrow.down", value: model.system.network.downloadBytesPerSec)
            rate("Upload", symbol: "arrow.up", value: model.system.network.uploadBytesPerSec)
        }
        .frame(width: Self.instrumentSize)
        .help("Live physical-interface traffic. Bars use a fixed logarithmic scale from 0 to 1 GB/s, not link utilization.")
    }

    private func rate(_ title: String, symbol: String, value: Double?) -> some View {
        let metric = QuickViewRate(bytesPerSecond: value)
        return VStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: symbol).foregroundStyle(.secondary)
                Text(metric.readout).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(FleetFont.mono(11))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: FleetMetrics.barCorner).fill(FleetColor.indicatorOff)
                    if let fraction = metric.fraction {
                        RoundedRectangle(cornerRadius: FleetMetrics.barCorner)
                            .fill(SketchInk.accent)
                            .frame(width: geometry.size.width * fraction)
                    }
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(metric.bytesPerSecond == nil ? "Unavailable" : metric.readout)
    }
}

/// A named control for one dropdown instrument. The column itself stays out of
/// the focus system: a focusable rectangle there strokes a hit box around the
/// meter as soon as the menu-bar dropdown is on screen.
private struct AgentHookButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("Agent")
                .font(FleetFont.sectionLabel)
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Investigate \(title) with agent")
        .accessibilityLabel("Investigate \(title) with agent")
    }
}
