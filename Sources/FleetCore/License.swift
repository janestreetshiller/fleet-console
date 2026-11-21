import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public enum PremiumFeature: String, CaseIterable, Sendable {
    case smcSensors
    case skipWelcomeAnimation
    case advancedHeatmapFilters
    case reconcile

    public var displayName: String {
        switch self {
        case .smcSensors: return "SMC fan & temperature sensors"
        case .skipWelcomeAnimation: return "Skip welcome animation"
        case .advancedHeatmapFilters: return "Advanced heatmap filters"
        case .reconcile: return "Reconcile — apply desired state"
        }
    }
}

public enum LicenseKey {
    public static let separator: Character = "."
    public static let versionPrefix = "FLT1-"

    public static let vendorSecret = "fleet-console-license-v1"

    public static func sign(payload: String, secret: String = vendorSecret) -> String {
        let signature = hmac(payload: payload, secret: secret)
        return "\(payload)\(separator)\(encodeBase32(signature))"
    }

    public static func isValid(key: String, secret: String = vendorSecret) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(versionPrefix) else { return false }
        let body = trimmed.dropFirst(versionPrefix.count)
        guard let cut = body.lastIndex(of: separator) else { return false }
        let payload = String(body[..<cut])
        let signature = String(body[body.index(after: cut)...])
        guard !payload.isEmpty, !signature.isEmpty else { return false }
        guard let expected = decodeBase32(signature),
              expected == hmac(payload: payload, secret: secret) else { return false }
        return payloadDate(payload) != nil
    }

    public static func issueDate(key: String, secret: String = vendorSecret) -> Date? {
        guard isValid(key: key, secret: secret) else { return nil }
        let body = key.trimmingCharacters(in: .whitespacesAndNewlines)
            .dropFirst(versionPrefix.count)
        guard let cut = body.lastIndex(of: separator) else { return nil }
        return payloadDate(String(body[..<cut]))
    }

    private static func payloadDate(_ payload: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: payload)
    }

    private static func hmac(payload: String, secret: String) -> [UInt8] {
        #if canImport(CryptoKit)
        let key = SymmetricKey(data: Data(secret.utf8))
        return Array(HMAC<SHA256>.authenticationCode(
            for: Data(payload.utf8), using: key))
        #else
        return []
        #endif
    }

    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func encodeBase32(_ bytes: [UInt8]) -> String {
        var result = ""
        var buffer = 0
        var bits = 0
        for byte in bytes {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                result.append(base32Alphabet[(buffer >> bits) & 0x1F])
            }
        }
        if bits > 0 {
            result.append(base32Alphabet[(buffer << (5 - bits)) & 0x1F])
        }
        return result
    }

    static func decodeBase32(_ string: String) -> [UInt8]? {
        var lookup: [Character: Int] = [:]
        for (index, character) in base32Alphabet.enumerated() {
            lookup[character] = index
        }
        var bytes: [UInt8] = []
        var buffer = 0
        var bits = 0
        for character in string.uppercased() {
            guard let value = lookup[character] else { return nil }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((buffer >> bits) & 0xFF))
            }
        }
        return bytes
    }
}

public enum TrialClock {
    public static let periodDays = 14

    public static func daysRemaining(since start: Date, now: Date,
                                     periodDays: Int = periodDays) -> Int {
        let elapsed = max(0, now.timeIntervalSince(start))
        let elapsedDays = Int(elapsed / 86_400)
        return max(0, periodDays - elapsedDays)
    }

    public static func isActive(since start: Date, now: Date,
                                periodDays: Int = periodDays) -> Bool {
        daysRemaining(since: start, now: now, periodDays: periodDays) > 0
    }
}

@Observable
@MainActor
public final class LicenseManager {
    public enum Status: Equatable, Sendable {
        case licensed(issued: Date?)
        case trial(daysRemaining: Int)
        case expired
    }

    public private(set) var status: Status

    private let defaults: UserDefaults
    private let now: () -> Date

    public static let suiteName = "com.fleetconsole.license"
    public static let trialStartKey = "trialStartDate"
    public static let licenseKeyKey = "licenseKey"

    public init(defaults: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard,
                now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        self.status = .expired
        refresh()
    }

    public var trialStart: Date {
        if let existing = defaults.object(forKey: Self.trialStartKey) as? Date {
            return existing
        }
        let start = now()
        defaults.set(start, forKey: Self.trialStartKey)
        return start
    }

    public var installedKey: String? {
        defaults.string(forKey: Self.licenseKeyKey)
    }

    public func refresh() {
        if let key = installedKey, LicenseKey.isValid(key: key) {
            status = .licensed(issued: LicenseKey.issueDate(key: key))
            return
        }
        let days = TrialClock.daysRemaining(since: trialStart, now: now())
        status = days > 0 ? .trial(daysRemaining: days) : .expired
    }

    @discardableResult
    public func install(key: String) -> Bool {
        guard LicenseKey.isValid(key: key) else { return false }
        defaults.set(key, forKey: Self.licenseKeyKey)
        refresh()
        return true
    }

    public func uninstall() {
        defaults.removeObject(forKey: Self.licenseKeyKey)
        refresh()
    }

    public func isUnlocked(_ feature: PremiumFeature) -> Bool {
        true
    }
}
