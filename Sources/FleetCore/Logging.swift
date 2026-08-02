import Foundation

/// Deliberately boring: line-oriented, timestamped, to stderr (launchd captures it)
/// and optionally to a 0600 file. No os_log subsystem, no remote sink.
public final class FleetLog {
    public enum Level: String {
        case debug = "DBG", info = "INF", warn = "WRN", error = "ERR"
    }

    public static let shared = FleetLog()
    private let queue = DispatchQueue(label: "fleet.log")
    private var fileHandle: FileHandle?
    public var minimumLevel: Level = .info

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    public func attachFile(at url: URL) {
        queue.sync {
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil,
                              attributes: [.posixPermissions: 0o600])
            }
            fileHandle = try? FileHandle(forWritingTo: url)
            _ = try? fileHandle?.seekToEnd()
        }
    }

    /// Keeps the daemon log from growing without bound; rotates at ~2 MB.
    public func rotateIfNeeded(at url: URL, limitBytes: Int = 2 * 1024 * 1024) {
        queue.sync {
            guard let size = try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? Int, size > limitBytes else { return }
            try? fileHandle?.close()
            let rotated = url.deletingPathExtension().appendingPathExtension("1.log")
            try? FileManager.default.removeItem(at: rotated)
            try? FileManager.default.moveItem(at: url, to: rotated)
            FileManager.default.createFile(atPath: url.path, contents: nil,
                                           attributes: [.posixPermissions: 0o600])
            fileHandle = try? FileHandle(forWritingTo: url)
        }
    }

    private func shouldLog(_ level: Level) -> Bool {
        let order: [Level] = [.debug, .info, .warn, .error]
        guard let a = order.firstIndex(of: level), let b = order.firstIndex(of: minimumLevel) else { return true }
        return a >= b
    }

    public func log(_ level: Level, _ message: String) {
        guard shouldLog(level) else { return }
        let line = "\(Self.formatter.string(from: Date())) [\(level.rawValue)] \(message)\n"
        queue.async {
            FileHandle.standardError.write(Data(line.utf8))
            if let handle = self.fileHandle {
                try? handle.write(contentsOf: Data(line.utf8))
            }
        }
    }

    public static func debug(_ m: @autoclosure () -> String) { shared.log(.debug, m()) }
    public static func info(_ m: @autoclosure () -> String) { shared.log(.info, m()) }
    public static func warn(_ m: @autoclosure () -> String) { shared.log(.warn, m()) }
    public static func error(_ m: @autoclosure () -> String) { shared.log(.error, m()) }
}
