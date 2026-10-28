import Foundation

/// Evidence that a controller generation was *told* to stop.
///
/// The controller records a `daemonStopping` event on its way out, and the next
/// generation reports "exited abnormally" when it finds a `daemonStarted` with
/// no stop after it. That inference is sound but the write was unreachable in
/// practice: `Controller.shutdown()` has to take the controller's serial queue
/// before it can touch the registry, a supervisor tick can hold that queue for
/// seconds doing health checks and `lsof`, and `launchctl bootout` follows its
/// SIGTERM with a SIGKILL long before the tick finishes. The stop event never
/// got written, so every deliberate restart was logged and displayed as a crash
/// — 56 signals against 3 clean stops in this install's own log, and a critical
/// "The controller has been restarting" item raised off the difference.
///
/// So intent is recorded separately from the graceful path, by the signal
/// handler itself, before any lock is taken: one `write(2)` to a file whose
/// presence means "a stop signal arrived". A real abnormal exit — SIGKILL with
/// no SIGTERM, a panic, power loss — still leaves no marker and is still
/// reported as one. The marker only ever suppresses the claim in the case where
/// the claim is false.
public enum StopMarker {
    /// Called from a signal handler, so this does the least possible work and
    /// never touches Foundation's higher-level file APIs.
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

    /// Reads the marker and removes it, so one signal can only ever explain one
    /// exit. Returns what the marker said, or nil if there was none.
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
