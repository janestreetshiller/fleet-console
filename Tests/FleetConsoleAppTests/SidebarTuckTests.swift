import Testing
@testable import FleetConsoleApp

struct SidebarTuckTests {
    @MainActor @Test func sidebarStartsOpenAndTogglingPreservesTheDestination() {
        let console = ConsoleModel()
        #expect(console.sidebarRevealed)
        console.open(.processes)
        console.search = "worker"
        console.selectedPID = 42
        console.toggleSidebar()
        #expect(!console.sidebarRevealed)
        console.toggleSidebar()
        #expect(console.sidebarRevealed)
        #expect(console.module == .processes)
        #expect(console.search == "worker")
        #expect(console.selectedPID == 42)
    }
}
