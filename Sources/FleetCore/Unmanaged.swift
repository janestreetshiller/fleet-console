import Foundation

// Processes the controller can see but did not start. An unmanaged row gets a
// name, a reason it was noticed and a "Reveal in Activity Monitor" — never a
// stop button.
// MARK: - Unmanaged processes

public enum UnmanagedReason: String, Codable, Sendable {
    case listenerNotInRegistry
    case devServerShape
    case escapedProcessGroup   // declared port still held after its owning group died

    public var label: String {
        switch self {
        case .listenerNotInRegistry: return "Listening port with no registry record"
        case .devServerShape: return "Dev-server-shaped process, not launched via controller"
        case .escapedProcessGroup: return "Port still held after its managed group exited"
        }
    }
}

public struct UnmanagedProcess: Codable, Sendable, Identifiable, Hashable {
    public var id: String          // stable key: "pid:startsig"
    public var pid: Int32
    public var command: String     // executable name
    public var commandLine: String // full argv, truncated
    public var user: String
    public var ports: [Int]
    public var firstSeen: Date
    public var lastSeen: Date
    public var reason: UnmanagedReason
    /// Set when this process was once managed by us (strongest possible signal of a leak).
    public var formerServiceID: String?

    public init(id: String, pid: Int32, command: String, commandLine: String, user: String,
                ports: [Int], firstSeen: Date, lastSeen: Date, reason: UnmanagedReason,
                formerServiceID: String? = nil) {
        self.id = id
        self.pid = pid
        self.command = command
        self.commandLine = commandLine
        self.user = user
        self.ports = ports
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.reason = reason
        self.formerServiceID = formerServiceID
    }
}
