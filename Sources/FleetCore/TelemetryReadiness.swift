import Foundation

/// Verification distinguishes unsupported hardware from a failed live probe.
public enum TelemetryReadiness {
    public static func power(probeSucceeded: Bool, hasBattery: Bool, charge: Double?) -> Bool {
        guard probeSucceeded else { return false }
        guard hasBattery else { return true }
        return charge.map { $0.isFinite && (0...1).contains($0) } == true
    }

    public static func network(probeSucceeded: Bool, hasActiveLink: Bool,
                               download: Double?, upload: Double?, historySamples: Int) -> Bool {
        guard probeSucceeded, historySamples >= 0 else { return false }
        guard hasActiveLink else { return true }
        return historySamples > 0
            && download.map { $0.isFinite && $0 >= 0 } == true
            && upload.map { $0.isFinite && $0 >= 0 } == true
    }
}
