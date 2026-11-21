import Foundation

public enum UnmanagedReason: String, Codable, Sendable {
    case listenerNotInRegistry
    case devServerShape
    case escapedProcessGroup

    public var label: String {
        switch self {
        case .listenerNotInRegistry: return "Listening port with no registry record"
        case .devServerShape: return "Dev-server-shaped process, not launched via controller"
        case .escapedProcessGroup: return "Port still held after its managed group exited"
        }
    }
}

public struct UnmanagedProcess: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var pid: Int32
    public var command: String
    public var commandLine: String
    public var user: String
    public var ports: [Int]
    public var firstSeen: Date
    public var lastSeen: Date
    public var reason: UnmanagedReason
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
