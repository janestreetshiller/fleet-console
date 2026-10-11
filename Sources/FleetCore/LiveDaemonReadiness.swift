import Foundation

/// Live-daemon verification requires a received snapshot, not an attempted RPC.
public enum LiveDaemonReadiness {
    public static func snapshot(connected: Bool, hasDaemon: Bool,
                                ageSeconds: TimeInterval?) -> Bool {
        guard connected, hasDaemon, let ageSeconds, ageSeconds.isFinite else { return false }
        return (0...15).contains(ageSeconds)
    }
}
