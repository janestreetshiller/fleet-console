import Foundation
import Testing
import FleetCore
@testable import FleetConsoleApp

struct AgentRegistrationComposerTests {
    @MainActor @Test("Registered IDs are usable task owners without a detected session")
    func registeredIDsAreTaskOwners() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registration = AgentRegistrationModel(fileURL: directory.appendingPathComponent("registered-agents.json"))
        registration.agentID = "Idle-worker"
        #expect(registration.register())
        let composer = TaskComposerModel(agentProfiles: [AgentProfile(id: "codex"), AgentProfile(id: "operator")],
                                         registration: registration)
        #expect(composer.agentOptions == ["operator", "Idle-worker", "codex"])
        #expect(composer.agentOptions.contains(composer.ownerAgent))
        composer.ownerAgent = "Idle-worker"
        composer.taskName = "Fixture task"
        composer.command = "/usr/bin/true"
        #expect(try #require(composer.validated()).ownerAgent == "Idle-worker")
        registration.agentID = "codex"
        #expect(registration.register())
        #expect(composer.agentOptions == ["operator", "Idle-worker", "codex"])
        registration.agentID = "later"
        #expect(registration.register())
        #expect(composer.agentOptions == ["operator", "Idle-worker", "codex", "later"])
    }

    @MainActor @Test("A removed selection falls back to operator, but real ownership remains selectable")
    func removedSelectionIsReconciled() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registration = AgentRegistrationModel(fileURL: directory.appendingPathComponent("registered-agents.json"))
        registration.agentID = "idle"
        #expect(registration.register())
        let composer = TaskComposerModel(registration: registration)
        composer.ownerAgent = "idle"
        #expect(registration.remove("idle"))
        composer.reconcileOwnerAgent()
        #expect(composer.agentOptions == ["operator"])
        #expect(composer.ownerAgent == "operator")
        registration.agentID = "codex"
        #expect(registration.register())
        let observedComposer = TaskComposerModel(agentProfiles: [AgentProfile(id: "codex")],
                                                 registration: registration)
        observedComposer.ownerAgent = "codex"
        #expect(registration.remove("codex"))
        observedComposer.reconcileOwnerAgent()
        #expect(observedComposer.ownerAgent == "codex")
    }
}
