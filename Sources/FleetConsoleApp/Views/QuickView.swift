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

    init(cpu: CPUSample, memory: MemorySample) {
        let cpuValue = cpu.sampled ? Self.validShare(cpu.usage) : nil
        let memoryValue = memory.totalBytes > 0 ? Self.validShare(memory.usedShare) : nil
        self.cpu = QuickViewDial(value: cpuValue,
                                 tone: cpuValue.map(SystemThresholds.utilization) ?? .unknown)
        self.memory = QuickViewDial(value: memoryValue,
                                    tone: memoryValue == nil ? .unknown : SystemThresholds.memory(memory))
    }

    private static func validShare(_ value: Double) -> Double? {
        value.isFinite && (0...1).contains(value) ? value : nil
    }
}

/// The menu-bar glance shares the dashboard's probes and bounded histories.
/// It draws two static dials, with no chart layout, extra timers or collectors.
struct QuickView: View {
    @Bindable var model: AppModel
    private static let dialDiameter: CGFloat = 90

    var body: some View {
        let metrics = QuickViewMetrics(cpu: model.system.cpu, memory: model.system.memory)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("This Mac").font(FleetFont.rowTitle)
                Spacer()
                Text(model.system.topology.brand)
                    .font(FleetFont.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                dial("CPU", metric: metrics.cpu, detail: model.system.topology.coreSummary)
                dial("Memory", metric: metrics.memory,
                     detail: metrics.memory.value == nil ? "Waiting for sample"
                         : ConsoleFmt.bytes(model.system.memory.usedBytes) + " used",
                     secondaryDetail: "Pressure " + model.system.memory.pressure.label)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Network").font(FleetFont.rowTitle)
                    Label(ConsoleFmt.byteRate(model.system.network.downloadBytesPerSec), systemImage: "arrow.down")
                    Label(ConsoleFmt.byteRate(model.system.network.uploadBytesPerSec), systemImage: "arrow.up")
                }
                .font(FleetFont.body).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            HStack {
                Text("\(model.runningServices.count) services running")
                Spacer()
                if model.criticalCount + model.warningCount > 0 {
                    Label("\(model.criticalCount + model.warningCount) need attention", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(StatusTone.warn.ink)
                } else {
                    Text("\(model.awaitingReplyCount) agent replies waiting")
                }
            }
            .font(FleetFont.caption).foregroundStyle(.secondary)
        }
        .padding(FleetMetrics.gutter)
        .accessibilityElement(children: .contain)
    }

    private func dial(_ title: String, metric: QuickViewDial, detail: String, secondaryDetail: String? = nil) -> some View {
        VStack(spacing: 6) {
            Text(title).font(FleetFont.rowTitle)
            RetroGauge(value: metric.value, tone: metric.tone, caption: title,
                       readout: metric.readout, diameter: Self.dialDiameter)
            Text(detail).font(FleetFont.caption).foregroundStyle(.secondary)
                .lineLimit(1)
            if let secondaryDetail {
                Text(secondaryDetail).font(FleetFont.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
