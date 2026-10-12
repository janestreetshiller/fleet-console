import AppKit
import Foundation
import Observation
import FleetCore

/// Shared by the Agents pane and task ownership picker. It has no daemon client
/// or polling task: a roster edit is only an atomic client-local file write.
@Observable
@MainActor
final class AgentRegistrationModel {
    static let shared = AgentRegistrationModel()

    private(set) var registeredIDs: [String] = []
    var agentID = ""
    private(set) var status: String?
    private(set) var statusIsError = false
    @ObservationIgnored private let store: AgentRegistrationStore

    init(fileURL: URL = FleetPaths.support.appendingPathComponent("registered-agents.json")) {
        store = AgentRegistrationStore(fileURL: fileURL)
        reload()
    }

    func reload() {
        do {
            registeredIDs = try store.load()
            status = nil
            statusIsError = false
        } catch {
            status = "Couldn't read agent IDs: \(error.localizedDescription)"
            statusIsError = true
        }
    }

    @discardableResult
    func register() -> Bool {
        do {
            registeredIDs = try store.register(agentID)
            status = "Registered “\(agentID)”."
            statusIsError = false
            agentID = ""
            return true
        } catch {
            status = error.localizedDescription
            statusIsError = true
            return false
        }
    }

    @discardableResult
    func copyID(_ id: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        let copied = pasteboard.setString(id, forType: .string)
        status = copied ? "Copied agent ID." : "Couldn't copy the agent ID. Try again."
        statusIsError = !copied
        return copied
    }

    @discardableResult
    func remove(_ id: String) -> Bool {
        do {
            registeredIDs = try store.remove(id)
            status = "Removed “\(id)” from registered IDs. Managed work is unchanged."
            statusIsError = false
            return true
        } catch {
            status = error.localizedDescription
            statusIsError = true
            return false
        }
    }
}
