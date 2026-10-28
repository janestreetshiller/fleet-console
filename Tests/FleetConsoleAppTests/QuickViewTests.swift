import Foundation
import Testing
@testable import FleetConsoleApp

struct QuickViewTests {
    @MainActor @Test func missingSamplesRemainUnavailable() {
        let metrics = QuickViewMetrics(cpu: CPUSample(), memory: MemorySample())
        #expect(metrics.cpu.value == nil)
        #expect(metrics.memory.value == nil)
        #expect(metrics.cpu.readout == "—")
        #expect(metrics.memory.readout == "—")
    }

    @MainActor @Test func idleIsARealReadingAndMemoryUsesCapacityShare() {
        var cpu = CPUSample(); cpu.sampled = true; cpu.usage = 0
        var memory = MemorySample(); memory.totalBytes = 16_000; memory.usedBytes = 8_000; memory.pressure = .normal
        let metrics = QuickViewMetrics(cpu: cpu, memory: memory)
        #expect(metrics.cpu.value == 0)
        #expect(metrics.cpu.readout == "0%")
        #expect(metrics.memory.value == 0.5)
        #expect(metrics.memory.readout == "50%")
    }

    @MainActor @Test func invalidReadingsStayUnavailable() {
        var cpu = CPUSample(); cpu.sampled = true; cpu.usage = .nan
        var memory = MemorySample(); memory.totalBytes = 8_000; memory.usedBytes = -1
        let metrics = QuickViewMetrics(cpu: cpu, memory: memory)
        #expect(metrics.cpu.value == nil)
        #expect(metrics.memory.value == nil)
    }

    @Test func quickViewHasOneStableMenuName() {
        #expect(FleetSection.quickView.menuTitle == "Quick View")
        #expect(FleetSection.allCases.first == .quickView)
    }
}
