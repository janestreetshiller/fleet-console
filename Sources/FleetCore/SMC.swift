import Foundation
#if canImport(IOKit)
import IOKit
#endif

public struct FanSample: Equatable, Sendable {
    public let index: Int
    public let rpm: Double?

    public init(index: Int, rpm: Double?) {
        self.index = index
        self.rpm = rpm
    }
}

public struct SensorSample: Equatable, Sendable {
    public let fans: [FanSample]
    public let cpuTempC: Double?
    public let gpuTempC: Double?
    public let available: Bool

    public init(fans: [FanSample] = [], cpuTempC: Double? = nil,
                gpuTempC: Double? = nil, available: Bool = false) {
        self.fans = fans
        self.cpuTempC = cpuTempC
        self.gpuTempC = gpuTempC
        self.available = available
    }

    public var maxRPM: Double? {
        fans.compactMap(\.rpm).max()
    }
}

public struct SMCKey: Equatable, Sendable {
    public let value: UInt32

    public init(_ string: String) {
        var bytes: [UInt8] = Array(string.utf8.prefix(4))
        while bytes.count < 4 { bytes.append(0) }
        value = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}

public enum SMCDataType: String, Sendable {
    case sp78
    case fpe2
    case flt = "flt "
}

public enum SMCDecode {
    public static func sp78(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 2 else { return nil }
        let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        return Double(raw) / 256.0
    }

    public static func fpe2(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 2 else { return nil }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return Double(raw) / 4.0
    }

    public static func float(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 4 else { return nil }
        let bits = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let value = Double(Float(bitPattern: bits))
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

public enum SMCKeys {
    public static let maxFans = 8

    public static func fanActual(_ index: Int) -> String { "F\(index)Ac" }

    public static let cpuTemperature: [(key: String, type: SMCDataType)] = [
        ("TC0P", .sp78),
        ("TC0D", .sp78),
        ("TC0E", .sp78),
        ("TC0F", .sp78),
        ("TC0c", .sp78),
        ("TCXC", .sp78),
    ]

    public static let gpuTemperature: [(key: String, type: SMCDataType)] = [
        ("TG0P", .sp78),
        ("TG0D", .sp78),
        ("TG0H", .sp78),
    ]
}

public final class SMCConnection: @unchecked Sendable {
    public enum SMCError: Error, Equatable {
        case serviceNotFound
        case openFailed(kern_return_t)
        case keyNotFound(String)
        case callFailed(kern_return_t)
    }

    #if canImport(IOKit)
    private var connection: io_connect_t = 0

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

    public static var ioStructSize: Int { MemoryLayout<KeyData>.stride }
    #endif

    public init() {}

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

    #if canImport(IOKit)
    public func read(key: SMCKey) throws -> (type: SMCDataType, bytes: [UInt8]) {
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
        infoInput.data8 = 9
        infoInput.key = key.value
        let info: KeyData
        do {
            info = try call(2, &infoInput)
        } catch {
            throw SMCError.keyNotFound(String(fourCC: key.value))
        }
        guard info.result == 0 else { throw SMCError.keyNotFound(String(fourCC: key.value)) }

        let size = Int(info.keyInfo.dataSize)
        guard size > 0 else { throw SMCError.keyNotFound(String(fourCC: key.value)) }

        var readInput = KeyData()
        readInput.data8 = 5
        readInput.key = key.value
        readInput.keyInfo = info.keyInfo
        let value = try call(2, &readInput)
        let bytes = withUnsafeBytes(of: value.bytes) { Array($0.prefix(size)) }

        let typeString = String(fourCC: value.keyInfo.dataType)
        guard let type = SMCDataType(rawValue: typeString) else {
            throw SMCError.keyNotFound(typeString)
        }
        return (type, bytes)
    }
    #endif
}

private extension String {
    init(fourCC: UInt32) {
        let scalars: [Unicode.Scalar] = (0..<4).compactMap { shift in
            let byte = UInt8((fourCC >> UInt32(24 - shift * 8)) & 0xFF)
            return byte == 0 ? nil : Unicode.Scalar(byte)
        }
        self = String(String.UnicodeScalarView(scalars))
    }
}

public final class SMCSampler: @unchecked Sendable {
    private let connection = SMCConnection()
    private var opened: Bool?

    public init() {}

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
        return SMCDecode.value(reading.bytes, as: reading.type)
        #else
        return nil
        #endif
    }
}
