import Foundation

/// Every path FleetConsole touches lives under the user's home, mode 0700/0600.
/// Nothing is written to /tmp, nothing is shared between users.
public enum FleetPaths {
    public static let bundleID = "com.fleetconsole"
    public static let agentLabel = "com.fleetconsole.fleetd"

    public static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FleetConsole", isDirectory: true)
    }

    public static var logs: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/FleetConsole", isDirectory: true)
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
