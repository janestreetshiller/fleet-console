import XCTest
@testable import FleetCore

final class SMCDecodingTests: XCTestCase {

    private func bytes(_ string: String) -> [UInt8] {
        Array(string.utf8)
    }

    func testKeyPacksFourCCBigEndian() {
        XCTAssertEqual(SMCKey("TC0P").value, 0x5443_3050)
        XCTAssertEqual(SMCKey("F0Ac").value, 0x4630_4163)
        XCTAssertEqual(SMCKey("TC0P"), SMCKey("TC0P"))
    }

    func testSP78BigEndian() {
        XCTAssertEqual(SMCDecode.sp78([0x32, 0x10]) ?? 0, 50.0625, accuracy: 0.001)
    }

    func testSP78IsSigned() {
        XCTAssertEqual(SMCDecode.sp78([0xFF, 0x00]) ?? 0, -1, accuracy: 0.001)
    }

    func testSP78ByteOrder() {
        XCTAssertEqual(SMCDecode.sp78([0x32, 0x10]) ?? 0, 50.0625, accuracy: 0.001)
        XCTAssertEqual(SMCDecode.sp78([0x10, 0x32]) ?? 0, 16.19, accuracy: 0.01)
    }

    func testSP78RejectsShortBuffers() {
        XCTAssertNil(SMCDecode.sp78([0x32]))
        XCTAssertNil(SMCDecode.sp78([]))
    }

    func testFPE2BigEndian() {
        XCTAssertEqual(SMCDecode.fpe2([0x19, 0x9E]) ?? 0, 1639.5, accuracy: 0.001)
    }

    func testFPE2ZeroIsAReading() {
        XCTAssertEqual(SMCDecode.fpe2([0x00, 0x00]), 0)
    }

    func testFloatBigEndian() {
        let bits = Float(50.0).bitPattern
        let wire: [UInt8] = [0x42, 0x48, 0x00, 0x00]
        XCTAssertEqual(SMCDecode.float(wire) ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(bits, 0x4248_0000)
    }

    func testFloatNaNIsAbsent() {
        XCTAssertNil(SMCDecode.float([0x7F, 0xC0, 0x00, 0x00]))
    }

    func testValueDispatchesByType() {
        XCTAssertEqual(SMCDecode.value([0x32, 0x10], as: .sp78) ?? 0, 50.0625, accuracy: 0.001)
        XCTAssertEqual(SMCDecode.value([0x19, 0x9E], as: .fpe2) ?? 0, 1639.5, accuracy: 0.001)
        XCTAssertEqual(SMCDecode.value([0x42, 0x48, 0, 0], as: .flt) ?? 0, 50, accuracy: 0.001)
    }
}

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
        let sample = SensorSample(fans: [.init(index: 0, rpm: nil)], available: true)
        XCTAssertNil(sample.maxRPM, "a fan with no reading is not a fan at zero")
    }
}

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
