import Foundation
#if canImport(IOKit)
import IOKit
#endif

// Fan and die temperatures from the System Management Controller.
//
// `ProcessInfo.thermalState` is a four-band summary and knows nothing about
// fans; the numbers a person actually asks about — "how fast is the fan
// spinning", "how hot is the die" — live in the SMC. Apple publishes none of
// this as API, so the key set below is the empirically stable subset: the
// same four-letter keys every SMC-equipped Mac has answered for a decade.
//
// The value *formats* are published folklore of a firmer kind: the kernel's
// own SMC client headers (AppleSMC Family) define `sp78` as a signed 7.8
// fixed-point degrees-C and `fpe2` as an unsigned 14.2 fixed-point RPM. Both
// are decoded big-endian, which is what the byte order on the wire has always
// been.
//
// Two machine classes answer "unknown", and both are real:
//   * VMs and very old Macs simply have no AppleSMC service in the I/O
//     Registry, so `open()` fails.
//   * Apple silicon Macs answer the connection but hold far fewer keys than
//     Intel machines did; a key that returns a zero-length value is treated
//     as absent rather than as a fan that is stopped or a die at 0 °C.
//
// Nothing here throws. A host without SMC data is a normal host, and the
// value types carry the absence explicitly.

// MARK: - Value types

/// One fan's reading. `rpm == nil` means the key was absent or answered with
/// no data — a stopped fan reports 0, so nil is never confused with stopped.
public struct FanSample: Equatable, Sendable {
    public let index: Int
    public let rpm: Double?

    public init(index: Int, rpm: Double?) {
        self.index = index
        self.rpm = rpm
    }
}

/// What the SMC knows about this host right now.
public struct SensorSample: Equatable, Sendable {
    public let fans: [FanSample]
    /// CPU die temperature in °C, nil when the key set answered nothing.
    public let cpuTempC: Double?
    /// GPU temperature in °C where the machine exposes one (Intel Macs with
    /// discrete graphics). Apple silicon reports no GPU key; nil, not 0.
    public let gpuTempC: Double?
    /// Whether the SMC connection itself opened. Distinguishes "no SMC on
    /// this machine" from "SMC answered, but it holds no keys we read".
    public let available: Bool

    public init(fans: [FanSample] = [], cpuTempC: Double? = nil,
                gpuTempC: Double? = nil, available: Bool = false) {
        self.fans = fans
        self.cpuTempC = cpuTempC
        self.gpuTempC = gpuTempC
        self.available = available
    }

    /// The loudest fan, for the one-line summary. Nil when no fan reported.
    public var maxRPM: Double? {
        fans.compactMap(\.rpm).max()
    }
}

// MARK: - Key layout

/// A four-character SMC key. Keys are compared by value, and building one
/// from a literal is a compile-time act, so this is a struct rather than four
/// loose bytes passed around.
public struct SMCKey: Equatable, Sendable {
    public let value: UInt32

    public init(_ string: String) {
        var bytes: [UInt8] = Array(string.utf8.prefix(4))
        while bytes.count < 4 { bytes.append(0) }
        value = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}

/// The data types this file knows how to decode. The SMC carries dozens more;
/// adding one is adding a case and a decoder, not touching the read path.
public enum SMCDataType: String, Sendable {
    /// Signed 7.8 fixed point — every temperature key on Intel Macs.
    case sp78
    /// Unsigned 14.2 fixed point — every fan-actual key.
    case fpe2
    /// IEEE 754 binary32 — the float encoding some Apple silicon keys use.
    case flt = "flt "
}

// MARK: - Decoding (pure, testable)

public enum SMCDecode {
    /// `sp78`: big-endian signed 7.8 fixed point. Two bytes, nothing else is
    /// well-formed; a short read is absent data, not a cold sensor.
    public static func sp78(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 2 else { return nil }
        let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        return Double(raw) / 256.0
    }

    /// `fpe2`: big-endian unsigned 14.2 fixed point.
    public static func fpe2(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 2 else { return nil }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return Double(raw) / 4.0
    }

    /// `flt `: a big-endian 32-bit float. SMC byte order is big-endian
    /// regardless of host endianness, so the bytes are assembled by hand.
    public static func float(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 4 else { return nil }
        let bits = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let value = Double(Float(bitPattern: bits))
        // A NaN in a temperature register is a sensor that failed; report it
        // as absent so it cannot render as a number.
        return value.isNaN ? nil : value
    }

    public static func value(_ bytes: [UInt8], as type: SMCDataType) -> Double? {
        switch type {
        case .sp78: return sp78(bytes)
        case .fpe2: return fpe2(bytes)
        case .flt: return float(bytes)
        }
    }
}

// MARK: - Key discovery (pure, testable)

public enum SMCKeys {
    /// Fan keys, in probe order. `F0Ac`/`F1Ac` cover every shipping layout
    /// (a Mac Pro reports more; the loop below is capped at what the UI can
    /// honestly show, and eight fans is past that).
    public static let maxFans = 8

    public static func fanActual(_ index: Int) -> String { "F\(index)Ac" }

    /// Temperature keys, most-preferred first. The first key that returns a
    /// value wins, so the order *is* the meaning: proximity sensors (TC0P)
    /// read a few degrees lower than die sensors (TC0D/TC0E/TC0F), and the
    /// die is what throttling is decided on.
    public static let cpuTemperature: [(key: String, type: SMCDataType)] = [
        ("TC0P", .sp78),   // CPU proximity — the most consistently present
        ("TC0D", .sp78),   // CPU die
        ("TC0E", .sp78),   // CPU die (multi-die parts)
        ("TC0F", .sp78),   // CPU die digital
        ("TC0c", .sp78),   // CPU core 0 (older Macs)
        ("TCXC", .sp78),   // PECI package (2018+ Intel)
    ]

    /// GPU keys. Absent on every Apple silicon machine and on integrated-only
    /// Intel Macs; the absence is the normal case.
    public static let gpuTemperature: [(key: String, type: SMCDataType)] = [
        ("TG0P", .sp78),   // GPU proximity
        ("TG0D", .sp78),   // GPU die
        ("TG0H", .sp78),   // GPU heatsink
    ]
}

// MARK: - Connection

/// One open connection to the AppleSMC service.
///
/// Reading is two round trips per key — read the key's descriptor for its
/// type and size, then read the value — because the size is how the SMC says
/// "I don't have that": a key it does not hold answers the descriptor call
/// with an error, which is the absence signal every probe above relies on.
public final class SMCConnection: @unchecked Sendable {
    public enum SMCError: Error, Equatable {
        /// No AppleSMC service in the I/O Registry (VMs, very old hardware).
        case serviceNotFound
        case openFailed(kern_return_t)
        case keyNotFound(String)
        case callFailed(kern_return_t)
    }

    #if canImport(IOKit)
    private var connection: io_connect_t = 0

    // This mirrors AppleSMC's SMCKeyData_t. The key-info fields are separate
    // fields in the kernel ABI; packing them into one UInt32 makes Swift send
    // a 60-byte struct and the driver rejects every call with invalid input
    // structure size. The ABI is 80 bytes, including the explicit padding.
    private struct KeyDataVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct KeyDataPLimit {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct KeyDataInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private typealias KeyBytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    private struct KeyData {
        var key: UInt32 = 0
        var vers = KeyDataVersion()
        var pLimitData = KeyDataPLimit()
        var keyInfo = KeyDataInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: KeyBytes = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    /// The input/output size required by the AppleSMC kernel ABI.
    public static var ioStructSize: Int { MemoryLayout<KeyData>.stride }
    #endif

    public init() {}

    /// Whether the SMC on this host can be talked to at all. Cached by the
    /// caller — `sample()` below is the cheap check for one polling loop.
    #if canImport(IOKit)
    public func open() throws {
        guard connection == 0 else { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw SMCError.openFailed(result) }
    }

    public func close() {
        guard connection != 0 else { return }
        IOServiceClose(connection)
        connection = 0
    }
    #else
    public func open() throws { throw SMCError.serviceNotFound }
    public func close() {}
    #endif

    /// One key read: descriptor for type and size, then the value. Absent
    /// keys throw `keyNotFound`; callers probing a list of keys catch it and
    /// move to the next.
    #if canImport(IOKit)
    public func read(key: SMCKey) throws -> (type: SMCDataType, bytes: [UInt8]) {
        // Kernel constants from AppleSMC Family, stable since the service
        // existed: 0 is the connection's own index, 5 is the "read one key"
        // selector, 9 is "describe this key".
        func call(_ selector: UInt32, _ input: inout KeyData) throws -> KeyData {
            var inputCopy = input
            var output = KeyData()
            var outputSize = MemoryLayout<KeyData>.stride
            let result = IOConnectCallStructMethod(
                connection, selector,
                &inputCopy, MemoryLayout<KeyData>.stride,
                &output, &outputSize)
            guard result == kIOReturnSuccess else { throw SMCError.callFailed(result) }
            return output
        }

        var infoInput = KeyData()
        infoInput.data8 = 9  // kSMCGetKeyInfo
        infoInput.key = key.value
        let info: KeyData
        do {
            info = try call(2, &infoInput)  // kSMCHandleYPCEvent
        } catch {
            throw SMCError.keyNotFound(String(fourCC: key.value))
        }
        guard info.result == 0 else { throw SMCError.keyNotFound(String(fourCC: key.value)) }

        let size = Int(info.keyInfo.dataSize)
        guard size > 0 else { throw SMCError.keyNotFound(String(fourCC: key.value)) }

        var readInput = KeyData()
        readInput.data8 = 5  // kSMCReadKey
        readInput.key = key.value
        readInput.keyInfo = info.keyInfo
        let value = try call(2, &readInput)
        let bytes = withUnsafeBytes(of: value.bytes) { Array($0.prefix(size)) }

        let typeString = String(fourCC: value.keyInfo.dataType)
        guard let type = SMCDataType(rawValue: typeString) else {
            // A type we do not decode is the same to the UI as no key: the
            // alternative is rendering a number we cannot vouch for.
            throw SMCError.keyNotFound(typeString)
        }
        return (type, bytes)
    }
    #endif
}

private extension String {
    /// Renders a big-endian four-char code back to its characters, for error
    /// messages that name the key that was missing.
    init(fourCC: UInt32) {
        let scalars: [Unicode.Scalar] = (0..<4).compactMap { shift in
            let byte = UInt8((fourCC >> UInt32(24 - shift * 8)) & 0xFF)
            return byte == 0 ? nil : Unicode.Scalar(byte)
        }
        self = String(String.UnicodeScalarView(scalars))
    }
}

// MARK: - Sampler

/// Reads the whole sensor set once. Owns its connection; the polling loop in
/// the app constructs one and reuses it, so the open cost is paid once.
public final class SMCSampler: @unchecked Sendable {
    private let connection = SMCConnection()
    private var opened: Bool?

    public init() {}

    /// One full read. Never throws: every failure mode lands in the sample as
    /// `available == false` or a nil field, because the UI's question is
    /// "what can I show", not "what went wrong".
    public func sample() -> SensorSample {
        if opened == nil {
            do {
                try connection.open()
                opened = true
            } catch {
                opened = false
            }
        }
        guard opened == true else { return SensorSample() }

        var fans: [FanSample] = []
        for index in 0..<SMCKeys.maxFans {
            if let value = try? readValue(SMCKey(SMCKeys.fanActual(index)), as: .fpe2) {
                fans.append(FanSample(index: index, rpm: value))
            }
        }
        let cpu = SMCKeys.cpuTemperature.lazy.compactMap {
            try? self.readValue(SMCKey($0.key), as: $0.type)
        }.first
        let gpu = SMCKeys.gpuTemperature.lazy.compactMap {
            try? self.readValue(SMCKey($0.key), as: $0.type)
        }.first

        return SensorSample(fans: fans, cpuTempC: cpu, gpuTempC: gpu, available: true)
    }

    private func readValue(_ key: SMCKey, as expected: SMCDataType) throws -> Double? {
        #if canImport(IOKit)
        let reading = try connection.read(key: key)
        // Trust the descriptor's type when it disagrees with what we asked
        // for: the SMC is the authority on its own encoding.
        return SMCDecode.value(reading.bytes, as: reading.type)
        #else
        return nil
        #endif
    }
}
