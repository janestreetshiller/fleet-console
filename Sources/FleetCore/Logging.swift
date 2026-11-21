import Foundation

public final class FleetLog: @unchecked Sendable {
    public enum Level: String, Sendable {
        case debug = "DBG", info = "INF", warn = "WRN", error = "ERR"

        fileprivate var rank: Int {
            switch self {
            case .debug: return 0
            case .info: return 1
            case .warn: return 2
            case .error: return 3
            }
        }
    }

    public static let shared = FleetLog()

    private let queue = DispatchQueue(label: "fleet.log")

    private var fileHandle: FileHandle?

    private let levelLock = NSLock()
    private var storedMinimumLevel: Level = .info

    public var minimumLevel: Level {
        get { levelLock.withLock { storedMinimumLevel } }
        set { levelLock.withLock { storedMinimumLevel = newValue } }
    }

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
        level.rank >= minimumLevel.rank
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
