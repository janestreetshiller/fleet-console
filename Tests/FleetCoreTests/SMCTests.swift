import XCTest
@testable import FleetCore

/// SMC value decoding is the part of the sensor pipeline that can be wrong
/// without the hardware noticing — the kernel just gives you bytes. These
/// tests pin the three encodings FleetConsole understands and the byte order
/// each one implies, because an sp78 read little-endian is a die at −1 °C
/// reported as 255 °C, which is a number you only question once.
final class SMCDecodingTests: XCTestCase {

    private func bytes(_ string: String) -> [UInt8] {
        Array(string.utf8)
    }

    // MARK: Key packing

    /// A key's bytes, read back big-endian, are the fourCC it was made from —
    /// this is the whole contract with the kernel, and it failing means every
    /// read below is reading the wrong key.
    func testKeyPacksFourCCBigEndian() {
        XCTAssertEqual(SMCKey("TC0P").value, 0x5443_3050)
        XCTAssertEqual(SMCKey("F0Ac").value, 0x4630_4163)
        XCTAssertEqual(SMCKey("TC0P"), SMCKey("TC0P"))
    }

    // MARK: sp78  (signed fixed-point 7.8, big-endian)

    func testSP78BigEndian() {
        // 50.0625 °C = 0x3210 in sp78: 50<<8 | 0x10, and 0x10/256 = 0.0625.
        XCTAssertEqual(SMCDecode.sp78([0x32, 0x10]) ?? 0, 50.0625, accuracy: 0.001)
    }

    func testSP78IsSigned() {
        // 0xFF00 is -1.0 °C, not 255 — a sensor below freezing is a real
        // reading, and treating the value as unsigned would report 255 °C.
        XCTAssertEqual(SMCDecode.sp78([0xFF, 0x00]) ?? 0, -1, accuracy: 0.001)
    }

    /// The byte-order canary: the two orders are both decodable, and only one
    /// is a plausible die temperature. 0x3210 read little-endian is 16.2 °C.
    func testSP78ByteOrder() {
        XCTAssertEqual(SMCDecode.sp78([0x32, 0x10]) ?? 0, 50.0625, accuracy: 0.001)
        XCTAssertEqual(SMCDecode.sp78([0x10, 0x32]) ?? 0, 16.19, accuracy: 0.01)
    }

    func testSP78RejectsShortBuffers() {
        XCTAssertNil(SMCDecode.sp78([0x32]))
        XCTAssertNil(SMCDecode.sp78([]))
    }

    // MARK: fpe2  (unsigned fixed-point 14.2, big-endian)

    func testFPE2BigEndian() {
        // 1639.5 rpm * 4 = 6558 = 0x199E, big-endian.
        XCTAssertEqual(SMCDecode.fpe2([0x19, 0x9E]) ?? 0, 1639.5, accuracy: 0.001)
    }

    func testFPE2ZeroIsAReading() {
        // A stopped fan is 0 rpm — real data, distinct from an absent key.
        XCTAssertEqual(SMCDecode.fpe2([0x00, 0x00]), 0)
    }

    // MARK: flt   (IEEE-754, big-endian on the wire)

    func testFloatBigEndian() {
        let bits = Float(50.0).bitPattern   // 0x4248_0000
        let wire: [UInt8] = [0x42, 0x48, 0x00, 0x00]
        XCTAssertEqual(SMCDecode.float(wire) ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(bits, 0x4248_0000)
    }

    func testFloatNaNIsAbsent() {
        // A NaN in a temperature register is a failed sensor; rendering it
        // would put "nan" in the UI.
        XCTAssertNil(SMCDecode.float([0x7F, 0xC0, 0x00, 0x00]))
    }

    // MARK: Dispatch

    func testValueDispatchesByType() {
        XCTAssertEqual(SMCDecode.value([0x32, 0x10], as: .sp78) ?? 0, 50.0625, accuracy: 0.001)
        XCTAssertEqual(SMCDecode.value([0x19, 0x9E], as: .fpe2) ?? 0, 1639.5, accuracy: 0.001)
        XCTAssertEqual(SMCDecode.value([0x42, 0x48, 0, 0], as: .flt) ?? 0, 50, accuracy: 0.001)
    }
}

/// `SensorSample` is what the UI actually renders, so its summaries are the
/// contract worth testing: an empty probe is unavailable, and the fastest fan
/// is the one the one-line summary names.
final class SensorSampleTests: XCTestCase {

    func testEmptyProbeIsUnavailable() {
        let sample = SensorSample()
        XCTAssertFalse(sample.available)
        XCTAssertNil(sample.maxRPM)
        XCTAssertNil(sample.cpuTempC)
        XCTAssertNil(sample.gpuTempC)
    }

    func testFastestFanWins() {
        let sample = SensorSample(
            fans: [.init(index: 0, rpm: 1200), .init(index: 1, rpm: 2400)],
            available: true)
        XCTAssertEqual(sample.maxRPM, 2400)
    }

    func testFanWithoutSpeedYieldsNoReading() {
        // A present key that refused a value is not a stopped fan. Rendering
        // 0 rpm for a fan the SMC would not quote is a false claim of failure.
        let sample = SensorSample(fans: [.init(index: 0, rpm: nil)], available: true)
        XCTAssertNil(sample.maxRPM, "a fan with no reading is not a fan at zero")
    }
}

/// The probed-key lists are part of the format contract: adding a key means
/// the sampler believes more hardware exists, and removing one is a silent
/// regression for a machine that has it.
final class SMCKeyListTests: XCTestCase {
    func testIOKitRequestUsesAppleSMCStructureSize() {
        #if canImport(IOKit)
        XCTAssertEqual(SMCConnection.ioStructSize, 80,
                       "AppleSMC rejects requests with the old 60-byte layout")
        #endif
    }

    func testFanKeysCoverKnownLayouts() {
        XCTAssertEqual(SMCKeys.fanActual(0), "F0Ac")
        XCTAssertEqual(SMCKeys.fanActual(3), "F3Ac")
        XCTAssertGreaterThanOrEqual(SMCKeys.maxFans, 2,
                                    "every dual-fan Mac must be coverable")
    }

    func testTemperatureKeysPreferProximityThenDie() {
        XCTAssertEqual(SMCKeys.cpuTemperature.first?.key, "TC0P",
                       "TC0P is the most consistently present CPU key")
        XCTAssertTrue(SMCKeys.cpuTemperature.contains { $0.key == "TC0D" })
        XCTAssertTrue(SMCKeys.gpuTemperature.contains { $0.key == "TG0P" })
    }
}
