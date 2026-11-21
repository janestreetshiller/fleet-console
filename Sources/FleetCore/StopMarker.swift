import Foundation

public enum StopMarker {
    public static func write(signal: Int32) {
        let path = FleetPaths.stopMarker.path
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { return }
        var line = "signal \(signal) at \(Date().timeIntervalSince1970)\n"
        line.withUTF8 { buffer in
            _ = Darwin.write(fd, buffer.baseAddress, buffer.count)
        }
        Darwin.close(fd)
    }

    @discardableResult
    public static func consume() -> String? {
        let url = FleetPaths.stopMarker
        let contents = try? String(contentsOf: url, encoding: .utf8)
        try? FileManager.default.removeItem(at: url)
        return contents?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: FleetPaths.stopMarker)
    }
}
