import AppKit
import Foundation
import Testing
import FleetCore
@testable import FleetConsoleApp

struct AgentRegistrationModelTests {
    @MainActor @Test("Registration publishes only successfully persisted IDs")
    func registrationPublishesPersistedIDs() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("registered-agents.json")
        let registration = AgentRegistrationModel(fileURL: url)
        #expect(registration.registeredIDs.isEmpty)
        registration.agentID = "Worker-01"
        #expect(registration.register())
        #expect(registration.agentID.isEmpty)
        #expect(registration.registeredIDs == ["Worker-01"])
        #expect(!registration.statusIsError)
        #expect(AgentRegistrationModel(fileURL: url).registeredIDs == ["Worker-01"])
    }

    @MainActor @Test("Removing a registration changes only the local roster")
    func removalPublishesPersistedIDs() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("registered-agents.json")
        let registration = AgentRegistrationModel(fileURL: url)
        registration.agentID = "worker"
        #expect(registration.register())
        #expect(registration.remove("worker"))
        #expect(registration.registeredIDs.isEmpty)
        #expect(AgentRegistrationModel(fileURL: url).registeredIDs.isEmpty)
        #expect(!registration.statusIsError)
        #expect(!registration.remove("worker"))
        #expect(registration.statusIsError)
    }

    @MainActor @Test("Copy preserves the exact agent ID without editing the roster")
    func copyPreservesExactID() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("registered-agents.json")
        let registration = AgentRegistrationModel(fileURL: url)
        registration.agentID = "Worker-01"
        #expect(registration.register())
        let original = try Data(contentsOf: url)
        let pasteboard = NSPasteboard(name: .init("FleetAgentRegistrationTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(registration.copyID("Worker-01", to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "Worker-01")
        #expect(!registration.statusIsError)
        #expect(try Data(contentsOf: url) == original)
    }

    @MainActor @Test("Invalid and duplicate registrations keep the input and saved IDs")
    func errorsPreserveInputAndRoster() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("registered-agents.json")
        let registration = AgentRegistrationModel(fileURL: url)
        registration.agentID = "worker"
        #expect(registration.register())
        let original = try Data(contentsOf: url)
        for id in ["worker", " worker", "a/b"] {
            registration.agentID = id
            #expect(!registration.register())
            #expect(registration.agentID == id)
            #expect(registration.registeredIDs == ["worker"])
            #expect(registration.statusIsError)
            #expect(registration.status != nil)
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @MainActor @Test("A real file write failure is reported without adding a phantom registration")
    func writeFailureDoesNotPublishID() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("not-a-directory")
        let sentinel = Data("preserve".utf8)
        try sentinel.write(to: blocker)
        let registration = AgentRegistrationModel(fileURL: blocker.appendingPathComponent("roster.json"))
        registration.agentID = "worker"
        #expect(!registration.register())
        #expect(registration.registeredIDs.isEmpty)
        #expect(registration.agentID == "worker")
        #expect(registration.statusIsError)
        #expect(try Data(contentsOf: blocker) == sentinel)
    }

    @MainActor @Test("A damaged roster stays unchanged and read errors are visible")
    func readFailureIsVisible() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("registered-agents.json")
        let damaged = Data("{broken".utf8)
        try damaged.write(to: url)
        let registration = AgentRegistrationModel(fileURL: url)
        #expect(registration.registeredIDs.isEmpty)
        #expect(registration.statusIsError)
        #expect(registration.status?.contains("Couldn't read agent IDs") == true)
        registration.agentID = "worker"
        #expect(!registration.register())
        #expect(try Data(contentsOf: url) == damaged)
    }
}
