import Foundation

/// Every path FleetConsole touches lives under the user's home, mode 0700/0600.
/// Nothing is written to /tmp, nothing is shared between users.
public enum FleetPaths {
    public static let bundleID = "com.fleetconsole"
    public static let agentLabel = "com.fleetconsole.fleetd"

    /// Environment variable naming a directory that stands in for the user's home.
    public static let stateRootVariable = "FLEETCONSOLE_STATE_ROOT"

    /// Where `support` and `logs` live. Setting `FLEETCONSOLE_STATE_ROOT` to an
    /// absolute path gives a development controller, CLI or client its own
    /// registry, socket and logs. Setting `HOME` does not: Foundation's home
    /// lookup ignores it on macOS, so a second controller would find the
    /// user's socket and exit. Unset or empty, every path is the user's own.
    public static var root: URL {
        if let override = ProcessInfo.processInfo.environment[stateRootVariable], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static var support: URL {
        root.appendingPathComponent("Library/Application Support/FleetConsole", isDirectory: true)
    }

    public static var logs: URL {
        root.appendingPathComponent("Library/Logs/FleetConsole", isDirectory: true)
    }

    public static var serviceLogs: URL { logs.appendingPathComponent("services", isDirectory: true) }
    public static var socket: URL { support.appendingPathComponent("fleetd.sock") }
    /// Written the instant a stop signal arrives, before any shutdown work — see
    /// `StopMarker`.
    public static var stopMarker: URL { support.appendingPathComponent("stopping") }
    public static var database: URL { support.appendingPathComponent("registry.sqlite3") }
    public static var config: URL { support.appendingPathComponent("config.json") }
    public static var daemonLog: URL { logs.appendingPathComponent("fleetd.log") }

    @discardableResult
    public static func ensureDirectories() throws -> Bool {
        let fm = FileManager.default
        for dir in [support, logs, serviceLogs] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            // createDirectory only applies attributes when it creates the directory.
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
        return true
    }

    public static func stdoutPath(for id: String) -> String {
        serviceLogs.appendingPathComponent("\(id).out").path
    }

    public static func stderrPath(for id: String) -> String {
        serviceLogs.appendingPathComponent("\(id).err").path
    }
}
