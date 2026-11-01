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

    @Test("The process presentation survives navigation away and back")
    @MainActor
    func processPresentationPersists() {
        let console = ConsoleModel()
        console.open(.processes)
        console.processView = .scatter
        console.open(.services)
        console.open(.processes)
        #expect(console.processView == .scatter)
        #expect(ConsoleModel.ProcessView.allCases.map(\.rawValue)
                == ["Relationships", "Table", "Heatmap", "Scatter"])
    }
    @MainActor @Test("Console inspection stays in place and switches targets unambiguously")
    func consoleInspection() {
        let console = ConsoleModel()
        console.inspectConsoleService("fixture-service")
        #expect(console.module == .overview)
        #expect(console.inspectorTarget() == .service("fixture-service"))
        console.inspectConsoleProcess(42)
        #expect(console.module == .overview)
        #expect(console.selectedServiceID == nil)
        #expect(console.inspectorTarget() == .process(42))
        #expect(console.inspectorRevealed)
        #expect(console.handleEscape())
        #expect(console.inspectorTarget() == .none)
    }

}
