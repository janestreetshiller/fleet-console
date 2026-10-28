import Foundation
import Testing
import FleetCore

struct AgentRegistrationTests {
    @Test("Registered IDs survive reopening the client-local roster")
    func registrationPersists() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("registered-agents.json")
        let store = AgentRegistrationStore(fileURL: url)

        #expect(try store.load().isEmpty)
        #expect(try store.register("codex-worker.01") == ["codex-worker.01"])
        #expect(try AgentRegistrationStore(fileURL: url).load() == ["codex-worker.01"])
    }

    @Test("Invalid IDs are rejected without creating a roster or normalizing input")
    func invalidRegistration() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("registered-agents.json")
        let store = AgentRegistrationStore(fileURL: url)
        for id in ["", " ", " worker", "worker ", "two workers", "worker\n", "a/b", "-flag", "é", String(repeating: "a", count: 129)] {
            #expect(throws: (any Error).self) { try store.register(id) }
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try store.register(String(repeating: "a", count: 128)).count == 1)
    }

    @Test("Duplicate IDs fail without a write; case-distinct IDs and sequential store instances are preserved")
    func duplicateRegistration() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("registered-agents.json")
        let store = AgentRegistrationStore(fileURL: url)
        try store.register("Worker")
        let original = try Data(contentsOf: url)
        #expect(throws: (any Error).self) { try store.register("Worker") }
        #expect(try Data(contentsOf: url) == original)
        #expect(try AgentRegistrationStore(fileURL: url).register("worker") == ["Worker", "worker"])
        #expect(try store.register("second") == ["Worker", "worker", "second"])
    }

    @Test("Removing an ID persists without removing other IDs")
    func removalPersists() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("registered-agents.json")
        let store = AgentRegistrationStore(fileURL: url)
        try store.register("first")
        try store.register("second")
        #expect(try store.remove("first") == ["second"])
        #expect(try AgentRegistrationStore(fileURL: url).load() == ["second"])
        #expect(throws: (any Error).self) { try store.remove("missing") }
        #expect(try store.remove("second").isEmpty)
        #expect(try AgentRegistrationStore(fileURL: url).load().isEmpty)
    }

    @Test("Damaged roster data is reported and never overwritten")
    func damagedRosterIsPreserved() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("registered-agents.json")
        let store = AgentRegistrationStore(fileURL: url)
        for content in ["{broken", "[\"valid\",\"invalid id\"]", "[\"valid\",\"valid\"]"] {
            let original = Data(content.utf8)
            try original.write(to: url)
            #expect(throws: (any Error).self) { try store.load() }
            #expect(throws: (any Error).self) { try store.register("another") }
            #expect(throws: (any Error).self) { try store.remove("valid") }
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test("The client roster is private to the current user after every write")
    func privatePermissions() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("registered-agents.json")
        let store = AgentRegistrationStore(fileURL: url)
        for id in ["first", "second"] {
            try store.register(id)
            let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            #expect(permissions?.intValue == 0o600)
        }
        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        #expect(directoryPermissions?.intValue == 0o700)
    }

    @Test("The roster merges exact profile IDs without inventing live evidence")
    func exactProfileMerge() throws {
        var active = AgentProfile(id: "Worker")
        active.running = 2
        active.owned = 2
        var differentlyCased = AgentProfile(id: "worker")
        differentlyCased.totalLaunched = 3
        let rows = AgentRosterEntry.merge(registeredIDs: ["Worker", "idle", "Worker"],
                                         profiles: [differentlyCased, active])
        #expect(rows.map(\.id) == ["Worker", "idle", "worker"])
        #expect(rows[0].isRegistered)
        #expect(rows[0].profile == active)
        #expect(rows[1].isRegistered)
        #expect(rows[1].profile == nil)
        #expect(!rows[2].isRegistered)
        #expect(rows[2].profile == differentlyCased)
        #expect(AgentRosterEntry.merge(registeredIDs: [], profiles: []).isEmpty)
    }

    @Test("The no-scroll glance has a fixed five-row budget and explicit overflow")
    func glanceBudgetAndOverflow() {
        let ids = (0..<8).map { "worker-\($0)" }
        let sessions = (0..<4).map { AgentSession(id: "session-\($0)", tool: "codex", pid: Int32($0 + 100)) }
        let roster = AgentGlanceRoster(registeredIDs: ids, profiles: [AgentProfile(id: "worker-0")], sessions: sessions)
        #expect(roster.totalCount == 12)
        #expect(roster.ownerCount == 8)
        #expect(roster.detectedCount == 4)
        #expect(roster.visibleEntries.count == 5)
        #expect(roster.overflowCount == 7)
        #expect(roster.visibleEntries.count + roster.overflowCount == roster.totalCount)
        #expect(roster.entries.count == roster.totalCount)
        #expect(AgentGlanceRoster(registeredIDs: [], profiles: [], sessions: []).overflowCount == 0)
        #expect(AgentGlanceRoster.maximumRows * 36 + 36 + 20 + 32 + 16 <= 300)
    }
}
