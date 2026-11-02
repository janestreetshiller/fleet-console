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
    @Test("Agent map search and service selection use the operations inspector")
    @MainActor
    func topologyInspector() {
        let console = ConsoleModel()
        console.open(.services)
        console.operationsSection = "Agents"
        #expect(console.searchPrompt == "Search owners, services, sessions")
        console.selectedServiceID = "observed-service"
        #expect(console.inspectorTarget() == .service("observed-service"))
    }

    @Test("Operations destination changes clear search while reopening preserves it")
    @MainActor
    func operationsSearch() {
        let console = ConsoleModel()
        console.openOperationsSection("Agents")
        console.search = "ouros"
        console.openOperationsSection("Agents")
        #expect(console.search == "ouros")
        console.openOperationsSection("Services")
        #expect(console.search.isEmpty)
        #expect(console.operationsSection == "Services")
    }

}
