import Foundation

public enum FleetPaths {
    public static let bundleID = "com.fleetconsole"
    public static let agentLabel = "com.fleetconsole.fleetd"

    public static let stateRootVariable = "FLEETCONSOLE_STATE_ROOT"

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
