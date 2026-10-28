import Foundation
import IOKit.ps

/// Internal-battery state, not a UPS or a peripheral battery. Hosts without an
/// internal battery leave charge and remaining time unavailable rather than 0.
public struct PowerSample: Sendable, Equatable {
    public let probeSucceeded: Bool
    public let hasBattery: Bool
    public let chargeFraction: Double?
    public let isCharging: Bool
    public let isPluggedIn: Bool
    /// Minutes until full when charging, until empty when on battery; otherwise nil.
    public let minutesRemaining: Int?

    public init(hasBattery: Bool = false, chargeFraction: Double? = nil,
                isCharging: Bool = false, isPluggedIn: Bool = false,
                minutesRemaining: Int? = nil, probeSucceeded: Bool = false) {
        self.probeSucceeded = probeSucceeded
        self.hasBattery = hasBattery
        self.chargeFraction = chargeFraction
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.minutesRemaining = minutesRemaining
    }
}

/// Decodes the IOPS descriptions used by the live sampler, not a synthetic DTO.
/// A nil collection represents a failed read.
public enum PowerSourceDecoder {
    public static func sample(descriptions: [[String: Any]]?) -> PowerSample {
        guard let descriptions else { return PowerSample() }
        for description in descriptions {
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  description[kIOPSIsPresentKey] as? Bool != false else { continue }

            var charge: Double?
            if let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue,
               let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue,
               current.isFinite, maximum.isFinite, current >= 0, maximum > 0 {
                charge = min(1, current / maximum)
            }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let state = description[kIOPSPowerSourceStateKey] as? String
            let pluggedIn = state == kIOPSACPowerValue
            var minutes: Int?
            if charging {
                minutes = (description[kIOPSTimeToFullChargeKey] as? NSNumber)?.intValue
            } else if state == kIOPSBatteryPowerValue {
                minutes = (description[kIOPSTimeToEmptyKey] as? NSNumber)?.intValue
            }
            // -1 means "still calculating" in the IOPS contract.
            if let value = minutes, value < 0 { minutes = nil }
            return PowerSample(hasBattery: true, chargeFraction: charge,
                               isCharging: charging, isPluggedIn: pluggedIn,
                               minutesRemaining: minutes, probeSucceeded: true)
        }
        return PowerSample(probeSucceeded: true)
    }
}

/// Physical-interface throughput. Nil is an absent interval, not an idle link.
public struct NetworkTrafficSample: Sendable, Equatable {
    /// A successful counter read can still lack an active link or a rate interval.
    public let probeSucceeded: Bool
    public let downloadBytesPerSec: Double?
    public let uploadBytesPerSec: Double?
    public let interfaceNames: [String]
    public let checkedAt: Date

    public init(downloadBytesPerSec: Double? = nil, uploadBytesPerSec: Double? = nil,
                interfaceNames: [String] = [], checkedAt: Date = Date(),
                probeSucceeded: Bool = false) {
        self.probeSucceeded = probeSucceeded
        self.downloadBytesPerSec = downloadBytesPerSec
        self.uploadBytesPerSec = uploadBytesPerSec
        self.interfaceNames = interfaceNames
        self.checkedAt = checkedAt
    }
}

/// Cumulative bytes from one link. Keep integers until after subtraction so a
/// small delta is not lost when a long-lived interface has very large counters.
public struct NetworkInterfaceCounters: Sendable, Equatable {
    public let receivedBytes: UInt64
    public let sentBytes: UInt64

    public init(receivedBytes: UInt64, sentBytes: UInt64) {
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
    }
}

/// Pure rate math; the caller owns sampling, the baseline and a monotonic clock.
public enum NetworkTrafficRates {
    /// Five missed 2-second ticks are a gap, not a useful current average.
    public static let maximumInterval: TimeInterval = 10

    public static func sample(current: [String: NetworkInterfaceCounters],
                              previous: [String: NetworkInterfaceCounters]?,
                              elapsed: TimeInterval,
                              checkedAt: Date = Date()) -> NetworkTrafficSample {
        let interfaces = current.keys.sorted()
        let unavailable = NetworkTrafficSample(interfaceNames: interfaces, checkedAt: checkedAt,
                                               probeSucceeded: true)
        guard let previous, !current.isEmpty, previous.count == current.count,
              elapsed.isFinite, elapsed > 0,
              elapsed <= maximumInterval else { return unavailable }

        var received = 0.0
        var sent = 0.0
        for (name, counters) in current {
            guard let baseline = previous[name] else { return unavailable }
            guard counters.receivedBytes >= baseline.receivedBytes,
                  counters.sentBytes >= baseline.sentBytes else { return unavailable }
            received += Double(counters.receivedBytes - baseline.receivedBytes)
            sent += Double(counters.sentBytes - baseline.sentBytes)
        }
        let download = received / elapsed
        let upload = sent / elapsed
        guard download.isFinite, upload.isFinite else { return unavailable }
        return NetworkTrafficSample(downloadBytesPerSec: download,
                                    uploadBytesPerSec: upload,
                                    interfaceNames: interfaces, checkedAt: checkedAt,
                                    probeSucceeded: true)
    }
}
