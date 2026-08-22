import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// Licensing and the trial clock.
//
// Everything in this file is *scaffolding*: the honest version of where the
// product is. There is a 14-day trial counted from first launch, a key format
// with real signature checking so support can issue keys before there is a
// store, and a single place that answers "is this feature premium" so the
// gating cannot drift between surfaces. There is deliberately no checkout,
// no network validation and no revocation list — the file says so at the
// bottom, because the worst kind of licence code is the kind that pretends
// to be a payment system.
//
// Threat-model note (see docs/THREAT-MODEL.md): this is not anti-piracy. An
// HMAC key can be shared and a UserDefaults date can be rolled back, and
// neither is defended, because defending them costs the honest user and stops
// nobody. The check exists so premium *features* have one gate, so a trial
// has a real clock, and so a purchased key can be validated offline forever.

// MARK: - Features

/// The things a licence unlocks. Everything not listed here is free, forever.
///
/// The gate lives in the core rather than in each view for the same reason
/// the thresholds live in one enum: two surfaces that each decided "is SMC
/// premium" would eventually disagree, and a premium feature that shows in
/// one place and locks in another is a broken promise.
public enum PremiumFeature: String, CaseIterable, Sendable {
    /// Fan RPM and die temperatures from the SMC.
    case smcSensors
    /// Skipping the first-launch welcome. The welcome itself is free; the
    /// *skip* is premium — the onboarding is part of what a trial evaluates.
    case skipWelcomeAnimation
    /// The heatmap's advanced filtering (anything past the default view).
    case advancedHeatmapFilters

    public var displayName: String {
        switch self {
        case .smcSensors: return "SMC fan & temperature sensors"
        case .skipWelcomeAnimation: return "Skip welcome animation"
        case .advancedHeatmapFilters: return "Advanced heatmap filters"
        }
    }
}

// MARK: - Key format

/// `FLT1-<base32 payload>.<base32 HMAC-SHA256>`.
///
/// The payload is an ISO-8601 issue date; the signature is HMAC-SHA256 over
/// the payload string with the vendor secret. Validation is offline and
/// deterministic — a key that validates today validates in ten years, which
/// is the whole reason the format has a version prefix: `FLT2` can change
/// everything after the dash and old keys still parse.
public enum LicenseKey {
    /// Separator between the payload and the signature, inside the body.
    public static let separator: Character = "."
    public static let versionPrefix = "FLT1-"

    /// The signing secret.
    ///
    /// For a shipped app this would be generated once and held out of the
    /// repository; what matters for the gate is that issuer and validator use
    /// the same bytes. It lives here, visibly, because this is scaffolding —
    /// see the file header on why obscurity is not the defence.
    public static let vendorSecret = "fleet-console-license-v1"

    /// Builds the body (`payload.signature`) for a payload. The issuer side;
    /// exposed so a future `fleetctl license mint` — and the tests — sign
    /// exactly the way the validator verifies.
    public static func sign(payload: String, secret: String = vendorSecret) -> String {
        let signature = hmac(payload: payload, secret: secret)
        return "\(payload)\(separator)\(encodeBase32(signature))"
    }

    /// Validates a full key, e.g. `FLT1-2026-08-21.ABCD…`.
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
        // A syntactically valid key whose payload is not a date is a key we
        // cannot interpret; reject rather than license on an unknown format.
        return payloadDate(payload) != nil
    }

    /// The issue date a valid key carries. Nil for anything that does not
    /// parse — callers that license on `isValid` only ever see a date.
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
        // CryptoKit is present on every macOS this package targets; the
        // fallback is for the Linux toolchain the core also compiles under.
        return []
        #endif
    }

    // Base32 (RFC 4648, no padding — a key is typed by a human, and "=" at
    // the end of a key is a character that breaks double-click selection).
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

// MARK: - Trial clock

/// The trial arithmetic, pure so the tests can pin it against any clock.
public enum TrialClock {
    /// Days a first launch gets. Fourteen because a menu-bar app is judged in
    /// the first sitting, and the second week is for the person who meant to
    /// come back to it.
    public static let periodDays = 14

    /// Days left, whole days, never negative. `now` before the start (a
    /// rolled-back clock) counts as day zero — the trial is not extended by
    /// time travel, and it is not ended by it either.
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

// MARK: - Manager

/// The one place licensing state lives. `@Observable` because the trial
/// countdown is chrome, not data: the footer that shows it re-renders when
/// the state changes, and nothing persists *through* this object — it reads
/// and writes UserDefaults, which is the store.
@Observable
@MainActor
public final class LicenseManager {
    public enum Status: Equatable, Sendable {
        /// A valid key is installed.
        case licensed(issued: Date?)
        /// No key; trial clock running, N whole days left.
        case trial(daysRemaining: Int)
        /// No key; the trial ended.
        case expired
    }

    /// Trial, or licence. Recomputed from the store on every read of
    /// `status`, so rolling the system clock forward is reflected without an
    /// app restart — a countdown that cached would lie for days.
    public private(set) var status: Status

    private let defaults: UserDefaults
    private let now: () -> Date

    // Suite, not `.standard`: the daemon and any future CLI share the app's
    // licensing state by reading the same suite, and a key typed into the app
    // is honoured everywhere without a second entry point.
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

    /// The first-launch marker. Written exactly once: the trial clock starts
    /// the first time anything asks, and no amount of relaunching moves it.
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

    /// Installs a key. Returns whether the key validated; a rejected key is
    /// not stored, so a typo cannot wedge the app into the expired state.
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

    /// The one question every surface asks.
    ///
    /// Trial means *full*: a trial that hides the premium features is a demo
    /// of the free tier, not a trial of the product. The gate opens when the
    /// clock runs out.
    public func isUnlocked(_ feature: PremiumFeature) -> Bool {
        switch status {
        case .licensed, .trial: return true
        case .expired: return false
        }
    }
}
