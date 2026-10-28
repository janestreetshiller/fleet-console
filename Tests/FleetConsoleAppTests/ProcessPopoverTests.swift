import Foundation
import Testing
@testable import FleetConsoleApp

struct ProcessPopoverTests {
    @Test func aSingleRankingCanSwitchBetweenCPUAndMemory() {
        let cpuHeavy = ProcessRow(id: 10, pid: 10, ppid: 1, pgid: 10, uid: 501, user: "demo",
                                  name: "worker", commandLine: "worker", cpuPercent: 80, residentBytes: 100,
                                  ports: [], startSignature: "fixture-a", stateField: "R")
        let memoryHeavy = ProcessRow(id: 20, pid: 20, ppid: 1, pgid: 20, uid: 501, user: "demo",
                                     name: "editor", commandLine: "editor", cpuPercent: 5, residentBytes: 2_000,
                                     ports: [], startSignature: "fixture-b", stateField: "S")
        #expect(ProcessWeight.cpu.ranked([memoryHeavy, cpuHeavy], limit: 10).map(\.pid) == [10, 20])
        #expect(ProcessWeight.memory.ranked([cpuHeavy, memoryHeavy], limit: 10).map(\.pid) == [20, 10])
        #expect(ProcessWeight.cpu.ranked([memoryHeavy, cpuHeavy], limit: 1).map(\.pid) == [10])
        #expect(ProcessWeight.cpu.ranked([cpuHeavy], limit: 0).isEmpty)
    }
}
