import Darwin
import XCTest
@testable import FleetCore

final class NativeNetworkCountersTests: XCTestCase {
    func testNativeAdapterPreservesByteCountersAboveUInt32Max() throws {
        var data = ifmibdata()
        data.ifmd_flags = UInt32(IFF_UP | IFF_RUNNING)
        data.ifmd_data.ifi_type = UInt8(IFT_ETHER)
        data.ifmd_data.ifi_ibytes = UInt64(UInt32.max) + 1_024
        data.ifmd_data.ifi_obytes = UInt64(UInt32.max) * 2 + 2_048

        let counters = try XCTUnwrap(NativeNetworkCounters.read(
            interfaces: [(name: "en0", index: 7)],
            readStatistics: { index in
                XCTAssertEqual(index, 7)
                return data
            }))
        let link = try XCTUnwrap(counters["en0"])
        XCTAssertEqual(link.receivedBytes, data.ifmd_data.ifi_ibytes)
        XCTAssertEqual(link.sentBytes, data.ifmd_data.ifi_obytes)
        XCTAssertGreaterThan(link.receivedBytes, UInt64(UInt32.max))
        XCTAssertGreaterThan(link.sentBytes, UInt64(UInt32.max))
    }

    func testNativeAdapterCountersCrossUInt32BoundaryWithoutReset() throws {
        let previousData = nativeData(received: UInt64(UInt32.max) - 1_024,
                                      sent: UInt64(UInt32.max) - 512)
        let currentData = nativeData(received: UInt64(UInt32.max) + 1_024,
                                     sent: UInt64(UInt32.max) + 512)
        let interfaces: [(name: String, index: UInt32)] = [("en0", 7)]
        let previous = try XCTUnwrap(NativeNetworkCounters.read(
            interfaces: interfaces, readStatistics: { _ in previousData }))
        let current = try XCTUnwrap(NativeNetworkCounters.read(
            interfaces: interfaces, readStatistics: { _ in currentData }))

        let sample = NetworkTrafficRates.sample(current: current, previous: previous, elapsed: 2)
        XCTAssertTrue(sample.probeSucceeded)
        XCTAssertEqual(sample.downloadBytesPerSec, 1_024)
        XCTAssertEqual(sample.uploadBytesPerSec, 512)
    }

    func testNativeAdapterFiltersNonPhysicalInterfaceNames() throws {
        let names = ["en0", "en12", "utun0", "lo0", "bridge0", "awdl0", "en", "en-1", "en0alias", "en１"]
        let interfaces = names.enumerated().map { (name: $0.element, index: UInt32($0.offset + 1)) }
        var queriedIndices: [UInt32] = []
        let counters = try XCTUnwrap(NativeNetworkCounters.read(
            interfaces: interfaces, readStatistics: { index in
                queriedIndices.append(index)
                return self.nativeData()
            }))
        XCTAssertEqual(counters.keys.sorted(), ["en0", "en12"])
        XCTAssertEqual(queriedIndices, [1, 2])
    }

    func testNativeAdapterRequiresActiveNonLoopbackEthernet() throws {
        let data: [UInt32: ifmibdata] = [
            1: nativeData(),
            2: nativeData(flags: UInt32(IFF_RUNNING)),
            3: nativeData(flags: UInt32(IFF_UP)),
            4: nativeData(flags: UInt32(IFF_UP | IFF_RUNNING | IFF_LOOPBACK)),
            5: nativeData(type: UInt8(IFT_LOOP)),
        ]
        let interfaces = (1...5).map { (name: "en\($0 - 1)", index: UInt32($0)) }
        let counters = try XCTUnwrap(NativeNetworkCounters.read(
            interfaces: interfaces, readStatistics: { data[$0] }))
        XCTAssertEqual(counters.keys.sorted(), ["en0"])
    }

    func testNativeAdapterReadFailureDoesNotPublishPartialOrZeroCounters() {
        let counters = NativeNetworkCounters.read(
            interfaces: [("en0", 1), ("en1", 2)],
            readStatistics: { $0 == 1 ? self.nativeData() : nil })
        XCTAssertNil(counters)
    }

    func testSuccessfulNativeReadWithNoActiveLinkKeepsRatesUnavailable() throws {
        let counters = try XCTUnwrap(NativeNetworkCounters.read(
            interfaces: [("en0", 1)], readStatistics: { _ in self.nativeData(flags: 0) }))
        XCTAssertTrue(counters.isEmpty)
        let sample = NetworkTrafficRates.sample(current: counters, previous: [:], elapsed: 2)
        XCTAssertTrue(sample.probeSucceeded)
        XCTAssertNil(sample.downloadBytesPerSec)
        XCTAssertNil(sample.uploadBytesPerSec)
    }

    private func nativeData(received: UInt64 = 123, sent: UInt64 = 456,
                            flags: UInt32 = UInt32(IFF_UP | IFF_RUNNING),
                            type: UInt8 = UInt8(IFT_ETHER)) -> ifmibdata {
        var data = ifmibdata()
        data.ifmd_flags = flags
        data.ifmd_data.ifi_type = type
        data.ifmd_data.ifi_ibytes = received
        data.ifmd_data.ifi_obytes = sent
        return data
    }
}
