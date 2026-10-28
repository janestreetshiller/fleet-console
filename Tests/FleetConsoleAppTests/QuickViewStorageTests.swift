import Foundation
import FleetCore
import Testing
@testable import FleetConsoleApp

struct QuickViewStorageTests {
    @MainActor @Test func diskShowsCapacityInsteadOfThroughput() {
        var storage = StorageSample()
        storage.totalBytes = 1_000
        storage.availableBytes = 80
        storage.readBytesPerSec = 0
        let metrics = QuickViewMetrics(cpu: CPUSample(), memory: MemorySample(), storage: storage)
        #expect(metrics.disk.value == 0.92)
        #expect(metrics.disk.readout == "92%")
        #expect(metrics.disk.tone == .warn)
        #expect(metrics.diskFilledCells == 18)
    }

    @MainActor @Test func absentOrInvalidCapacityStaysUnavailable() {
        var storage = StorageSample()
        #expect(QuickViewMetrics(cpu: CPUSample(), memory: MemorySample(), storage: storage).disk.value == nil)
        storage.totalBytes = 1_000
        storage.availableBytes = -1
        #expect(QuickViewMetrics(cpu: CPUSample(), memory: MemorySample(), storage: storage).disk.value == nil)
        storage.availableBytes = 1_001
        #expect(QuickViewMetrics(cpu: CPUSample(), memory: MemorySample(), storage: storage).disk.value == nil)
    }
}
