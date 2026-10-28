import Foundation
import Testing
import FleetCore
@testable import FleetConsoleApp

struct FixtureRegistrationTests {
    @MainActor @Test func popoverAndComposerKeepInjectedRosterAfterReload() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let privateRoster = AgentRegistrationModel(fileURL: directory.appendingPathComponent("private.json"))
        privateRoster.agentID = "private-owner-fixture"
        #expect(privateRoster.register())
        let demoRoster = AgentRegistrationModel(fileURL: directory.appendingPathComponent("demo.json"))
        demoRoster.agentID = "demo-worker"
        #expect(demoRoster.register())
        let popover = FleetPopover(model: AppModel(), openDashboard: {}, registration: demoRoster)
        let composer = TaskComposerModel(agentProfiles: [], registration: demoRoster)
        popover.registration.reload()
        #expect(popover.registration === demoRoster)
        #expect(popover.registration.registeredIDs == ["demo-worker"])
        #expect(composer.agentOptions == ["operator", "demo-worker"])
        #expect(!composer.agentOptions.contains("private-owner-fixture"))
        #expect(privateRoster.registeredIDs == ["private-owner-fixture"])
    }
}
