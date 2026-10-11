import Testing
@testable import FleetConsoleApp

struct ConsoleNavigationTests {
    @Test("Home returns from a remote device to local attention")
    @MainActor
    func homeFromRemoteDevice() {
        let console = ConsoleModel()
        console.selectedDeviceID = "review-remote-device"
        console.goHome()
        #expect(console.isLocalDeviceSelected)
        #expect(console.atHome)
    }

    @Test("A module command leaves remote detail and selects the requested module")
    @MainActor
    func moduleFromRemoteDevice() {
        let console = ConsoleModel()
        console.selectedDeviceID = "review-remote-device"
        console.open(.processes)
        #expect(console.isLocalDeviceSelected)
        #expect(console.module == .processes)
        #expect(!console.atHome)
    }

    @Test("Changing destinations clears a filter from the previous module")
    @MainActor
    func moduleChangeClearsSearch() {
        let console = ConsoleModel()
        console.open(.processes)
        console.search = "65736"
        console.open(.services)
        #expect(console.search.isEmpty)
    }

    @Test("Reopening the same destination preserves its filter")
    @MainActor
    func sameModulePreservesSearch() {
        let console = ConsoleModel()
        console.open(.processes)
        console.search = "FleetConsole"
        console.open(.processes)
        #expect(console.search == "FleetConsole")
    }
}
