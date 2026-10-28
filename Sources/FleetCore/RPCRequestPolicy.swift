import Foundation

/// An observational client must never modify the controller's registry.
/// The default remains interactive for the app and CLI's normal workflows.
public enum RPCRequestPolicy: Equatable, Sendable {
    case interactive
    case observational

    public static func forArguments(_ arguments: [String]) -> Self {
        arguments.contains("--verify-live") ? .observational : .interactive
    }

    /// The renderer's missing-daemon probe must not change an interactive or
    /// normally compiled client's destination, even if it receives these flags.
    public static func daemonSocketPath(forArguments arguments: [String],
                                        surfaceRenderer: Bool,
                                        defaultPath: String = FleetPaths.socket.path) -> String {
        guard surfaceRenderer, forArguments(arguments) == .observational,
              let index = arguments.firstIndex(of: "--verify-daemon-socket"),
              index + 1 < arguments.count else { return defaultPath }
        return arguments[index + 1]
    }

    public func allows(_ operation: RPCOp) -> Bool {
        switch self {
        case .interactive: return true
        case .observational:
            switch operation {
            case .ping, .snapshot, .subscribe, .events, .logs, .messages: return true
            default: return false
            }
        }
    }
}
