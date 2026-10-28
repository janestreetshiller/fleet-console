import Foundation
import Observation
import Testing
import FleetCore
@testable import FleetConsoleApp

struct ServiceLabelsStoreTests {
    private func location() -> URL {
        let scratch = ProcessInfo.processInfo.environment["TMPDIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        return scratch.appendingPathComponent("fleet-service-labels-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("labels.json")
    }

    private func record() -> ServiceRecord {
        ServiceRecord(id: "service-a", friendlyName: "worker-api", ownerAgent: "claude",
                      purpose: "serve requests", command: ["python3", "server.py"],
                      cwd: "/fixture/project", pid: 4242, declaredPorts: [8787],
                      leaseExpiresAt: Date().addingTimeInterval(3600), leaseTTLSec: 3600)
    }

    @Test("Opening a new label store does not create preferences")
    @MainActor
    func firstReadHasNoWrites() {
        let path = location()
        let store = ServiceLabelsStore(path: path)
        #expect(store.loadError == nil)
        #expect(store.label(for: "missing") == ServiceLabel())
        #expect(!FileManager.default.fileExists(atPath: path.deletingLastPathComponent().path))
    }

    @Test("Saving a label notifies clients observing that service")
    @MainActor
    func publishedChanges() async throws {
        let path = location()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let store = ServiceLabelsStore(path: path)
        try await confirmation(expectedCount: 1) { changed in
            withObservationTracking {
                _ = store.label(for: "service-a")
            } onChange: {
                changed()
            }
            try store.set(ServiceLabel(name: "Local API"), for: "service-a")
        }
    }

    @Test("A failed save keeps the draft and does not publish an unsaved label")
    @MainActor
    func failedSaveKeepsDraft() throws {
        let path = location()
        let parent = path.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = ServiceLabelsStore(path: path)
        let editor = ServiceLabelEditorModel(service: record(), labels: store)
        editor.name = "Local API"
        editor.color = .pink
        try Data("not a directory".utf8).write(to: parent)
        #expect(!editor.save())
        #expect(editor.errorMessage != nil)
        #expect(editor.name == "Local API")
        #expect(editor.color == .pink)
        #expect(store.label(for: "service-a") == ServiceLabel())
        #expect(try String(contentsOf: parent, encoding: .utf8) == "not a directory")
    }

    @Test("An editor starts with saved labels and can restore the recorded name")
    @MainActor
    func editorLoadsAndResets() throws {
        let path = location()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let store = ServiceLabelsStore(path: path)
        try store.set(ServiceLabel(name: "Local API", color: .blue), for: "service-a")
        let editor = ServiceLabelEditorModel(service: record(), labels: store)
        #expect(editor.name == "Local API")
        #expect(editor.color == .blue)
        #expect(!editor.hasChanges)
        editor.name = ""
        editor.color = nil
        #expect(editor.hasChanges)
        #expect(editor.save())
        #expect(!editor.hasChanges)
        #expect(store.displayName(for: record()) == "worker-api")
    }

    @Test("Name and tag edits remain a draft until Save")
    @MainActor
    func editingIsLocalUntilSaved() throws {
        let path = location()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let store = ServiceLabelsStore(path: path)
        let service = record()
        let editor = ServiceLabelEditorModel(service: service, labels: store)
        #expect(!editor.hasChanges)
        editor.name = "Local API"
        editor.color = .purple
        #expect(editor.hasChanges)
        #expect(store.label(for: service.id) == ServiceLabel())
        #expect(!FileManager.default.fileExists(atPath: path.path))
        #expect(editor.save())
        #expect(store.label(for: service.id) == ServiceLabel(name: "Local API", color: .purple))
    }

    @Test("Presentation overrides do not modify controller records")
    @MainActor
    func displayNameUsesStableIdentity() throws {
        let path = location()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let store = ServiceLabelsStore(path: path)
        var service = record()
        #expect(store.displayName(for: service) == "worker-api")
        try store.set(ServiceLabel(name: "Local API", color: .purple), for: service.id)
        #expect(store.displayName(for: service) == "Local API")
        #expect(service.friendlyName == "worker-api")
        #expect(service.state == .starting)
        service.pid = 5252
        service.friendlyName = "worker-api-v2"
        #expect(store.displayName(for: service) == "Local API")
        service.id = "SERVICE-A"
        #expect(store.displayName(for: service) == "worker-api-v2")
    }

    @Test("Service search recognizes friendly names and tags without losing original facts")
    @MainActor
    func searchIncludesLabels() throws {
        let path = location()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let store = ServiceLabelsStore(path: path)
        let service = record()
        try store.set(ServiceLabel(name: "Local API", color: .purple), for: service.id)
        for query in [" local api \n", "PURPLE", "worker-api", "claude", "serve", "server.py", "8787", "4242", ""] {
            #expect(store.matches(query, record: service), "Did not match \(query)")
        }
        #expect(!store.matches("missing", record: service))
    }

    @Test("Service labels are stored privately")
    @MainActor
    func privateFilePermissions() throws {
        let path = location()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let store = ServiceLabelsStore(path: path)
        try store.set(ServiceLabel(name: "Local API"), for: "service-a")
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("Clearing a name and tag restores the default without retaining an empty override")
    @MainActor
    func resetLabel() throws {
        let path = location()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let store = ServiceLabelsStore(path: path)
        try store.set(ServiceLabel(name: "Local API", color: .purple), for: "service-a")
        try store.set(ServiceLabel(color: .teal), for: "service-b")
        try store.set(ServiceLabel(name: " \n "), for: "service-a")
        let data = try Data(contentsOf: path)
        let persisted = try JSONDecoder().decode([String: ServiceLabel].self, from: data)
        #expect(persisted["service-a"] == nil)
        #expect(persisted["service-b"] == ServiceLabel(color: .teal))
        #expect(store.label(for: "service-a") == ServiceLabel())
    }

    @Test("An unreadable label file is never silently overwritten")
    @MainActor
    func corruptedFileIsPreserved() throws {
        let path = location()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("not valid JSON".utf8)
        try original.write(to: path)
        let store = ServiceLabelsStore(path: path)
        #expect(throws: (any Error).self) {
            try store.set(ServiceLabel(name: "Local API", color: .blue), for: "service-a")
        }
        #expect(try Data(contentsOf: path) == original)
        #expect(store.label(for: "service-a") == ServiceLabel())
    }

    @Test("Friendly name and color survive a new client store")
    @MainActor
    func persistedLabels() throws {
        let path = location()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let store = ServiceLabelsStore(path: path)
        try store.set(ServiceLabel(name: " Local API ", color: .purple), for: "service-a")
        let reopened = ServiceLabelsStore(path: path)
        #expect(reopened.label(for: "service-a") == ServiceLabel(name: "Local API", color: .purple))
        #expect(reopened.label(for: "service-b") == ServiceLabel())
    }
}
