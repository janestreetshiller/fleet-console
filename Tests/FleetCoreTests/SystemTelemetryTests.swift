import Foundation
import IOKit.ps
import XCTest
@testable import FleetCore

final class SystemTelemetryTests: XCTestCase {
    func testNetworkProbeDistinguishesUnreadFromSuccessfulEmptyRead() {
        XCTAssertFalse(NetworkTrafficSample().probeSucceeded)

        let sample = NetworkTrafficRates.sample(current: [:], previous: nil, elapsed: 0)
        XCTAssertTrue(sample.probeSucceeded)
        XCTAssertTrue(sample.interfaceNames.isEmpty)
        XCTAssertNil(sample.downloadBytesPerSec)
        XCTAssertNil(sample.uploadBytesPerSec)
    }

    func testNetworkRatesUseElapsedTimeAndAggregateInterfaces() throws {
        let checkedAt = Date(timeIntervalSince1970: 123)
        let previous = [
            "en1": NetworkInterfaceCounters(receivedBytes: 100, sentBytes: 200),
            "en0": NetworkInterfaceCounters(receivedBytes: 1_000, sentBytes: 2_000),
        ]
        let current = [
            "en0": NetworkInterfaceCounters(receivedBytes: 3_000, sentBytes: 3_000),
            "en1": NetworkInterfaceCounters(receivedBytes: 600, sentBytes: 450),
        ]

        let sample = NetworkTrafficRates.sample(current: current, previous: previous,
                                                elapsed: 2.5, checkedAt: checkedAt)

        XCTAssertTrue(sample.probeSucceeded)
        XCTAssertEqual(try XCTUnwrap(sample.downloadBytesPerSec), 1_000, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(sample.uploadBytesPerSec), 500, accuracy: 0.001)
        XCTAssertEqual(sample.interfaceNames, ["en0", "en1"])
        XCTAssertEqual(sample.checkedAt, checkedAt)
    }

    func testCounterResetInvalidatesTheInterval() {
        let previous = ["en0": NetworkInterfaceCounters(receivedBytes: 1_000, sentBytes: 1_000)]
        let resets: [NetworkInterfaceCounters] = [
            .init(receivedBytes: 900, sentBytes: 1_100),
            .init(receivedBytes: 1_100, sentBytes: 900),
        ]
        for reset in resets {
            let current = ["en0": reset]
            let sample = NetworkTrafficRates.sample(current: current, previous: previous, elapsed: 2)
            XCTAssertTrue(sample.probeSucceeded)
            XCTAssertNil(sample.downloadBytesPerSec)
            XCTAssertNil(sample.uploadBytesPerSec)

            let recovered = NetworkTrafficRates.sample(
                current: ["en0": .init(receivedBytes: reset.receivedBytes + 400,
                                       sentBytes: reset.sentBytes + 200)],
                previous: current, elapsed: 2)
            XCTAssertEqual(recovered.downloadBytesPerSec, 200)
            XCTAssertEqual(recovered.uploadBytesPerSec, 100)
        }
    }

    func testInvalidElapsedTimeDoesNotReportAFalseRate() {
        let previous = ["en0": NetworkInterfaceCounters(receivedBytes: 1_000, sentBytes: 1_000)]
        let current = ["en0": NetworkInterfaceCounters(receivedBytes: 3_000, sentBytes: 2_000)]
        let intervals: [TimeInterval] = [0, -1, .nan, .infinity, 10.001, .leastNonzeroMagnitude]
        for elapsed in intervals {
            let sample = NetworkTrafficRates.sample(current: current, previous: previous, elapsed: elapsed)
            XCTAssertTrue(sample.probeSucceeded, "elapsed: \(elapsed)")
            XCTAssertNil(sample.downloadBytesPerSec, "elapsed: \(elapsed)")
            XCTAssertNil(sample.uploadBytesPerSec, "elapsed: \(elapsed)")
        }

        let boundary = NetworkTrafficRates.sample(current: current, previous: previous, elapsed: 10)
        XCTAssertEqual(boundary.downloadBytesPerSec, 200)
        XCTAssertEqual(boundary.uploadBytesPerSec, 100)
    }

    func testMissingOrChangedInterfaceBaselineIsUnavailable() {
        let counters = NetworkInterfaceCounters(receivedBytes: 1_000, sentBytes: 2_000)
        let snapshots: [(current: [String: NetworkInterfaceCounters],
                         previous: [String: NetworkInterfaceCounters]?)] = [
            (["en0": counters], nil),
            (["en0": counters], [:]),
            ([:], ["en0": counters]),
            ([:], [:]),
            (["en0": counters, "en1": counters], ["en0": counters]),
            (["en0": counters], ["en0": counters, "en1": counters]),
            (["en1": counters], ["en0": counters]),
        ]
        for (current, previous) in snapshots {
            let sample = NetworkTrafficRates.sample(current: current, previous: previous, elapsed: 2)
            XCTAssertTrue(sample.probeSucceeded)
            XCTAssertNil(sample.downloadBytesPerSec)
            XCTAssertNil(sample.uploadBytesPerSec)
            XCTAssertEqual(sample.interfaceNames, current.keys.sorted())
        }
    }

    func testIdleInterfaceReportsMeasuredZero() {
        let counters = ["en0": NetworkInterfaceCounters(receivedBytes: 123, sentBytes: 456)]
        let sample = NetworkTrafficRates.sample(current: counters, previous: counters, elapsed: 2)
        XCTAssertTrue(sample.probeSucceeded)
        XCTAssertEqual(sample.downloadBytesPerSec, 0)
        XCTAssertEqual(sample.uploadBytesPerSec, 0)
    }

    func testSmallDeltasSurviveVeryLargeCounters() {
        let previous = ["en0": NetworkInterfaceCounters(receivedBytes: .max - 128, sentBytes: .max - 256)]
        let current = ["en0": NetworkInterfaceCounters(receivedBytes: .max - 64, sentBytes: .max - 128)]
        let sample = NetworkTrafficRates.sample(current: current, previous: previous, elapsed: 2)
        XCTAssertEqual(sample.downloadBytesPerSec, 32)
        XCTAssertEqual(sample.uploadBytesPerSec, 64)
    }

    func testAggregatingLargeCountersDoesNotOverflow() {
        let previous = [
            "en0": NetworkInterfaceCounters(receivedBytes: 0, sentBytes: 0),
            "en1": NetworkInterfaceCounters(receivedBytes: 0, sentBytes: 0),
        ]
        let current = [
            "en0": NetworkInterfaceCounters(receivedBytes: .max, sentBytes: .max),
            "en1": NetworkInterfaceCounters(receivedBytes: .max, sentBytes: .max),
        ]
        let sample = NetworkTrafficRates.sample(current: current, previous: previous, elapsed: 2)
        XCTAssertEqual(sample.downloadBytesPerSec, Double(UInt64.max))
        XCTAssertEqual(sample.uploadBytesPerSec, Double(UInt64.max))
    }

    func testChargingBatteryDescriptionUsesTimeToFull() {
        let description: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSIsPresentKey: true,
            kIOPSCurrentCapacityKey: NSNumber(value: 40),
            kIOPSMaxCapacityKey: NSNumber(value: 80),
            kIOPSIsChargingKey: true,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
            kIOPSTimeToFullChargeKey: NSNumber(value: 35),
            kIOPSTimeToEmptyKey: NSNumber(value: 99),
        ]
        let sample = PowerSourceDecoder.sample(descriptions: [description])
        XCTAssertTrue(sample.probeSucceeded)
        XCTAssertTrue(sample.hasBattery)
        XCTAssertEqual(sample.chargeFraction, 0.5)
        XCTAssertTrue(sample.isCharging)
        XCTAssertTrue(sample.isPluggedIn)
        XCTAssertEqual(sample.minutesRemaining, 35)
    }

    func testDischargingBatteryDescriptionUsesTimeToEmpty() {
        let description: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSIsPresentKey: NSNumber(value: true),
            kIOPSCurrentCapacityKey: NSNumber(value: 40),
            kIOPSMaxCapacityKey: NSNumber(value: 80),
            kIOPSIsChargingKey: NSNumber(value: false),
            kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
            kIOPSTimeToFullChargeKey: NSNumber(value: 35),
            kIOPSTimeToEmptyKey: NSNumber(value: 99),
        ]
        let sample = PowerSourceDecoder.sample(descriptions: [
            [kIOPSTypeKey: kIOPSUPSType, kIOPSIsPresentKey: true],
            description,
        ])
        XCTAssertTrue(sample.probeSucceeded)
        XCTAssertTrue(sample.hasBattery)
        XCTAssertEqual(sample.chargeFraction, 0.5)
        XCTAssertFalse(sample.isCharging)
        XCTAssertFalse(sample.isPluggedIn)
        XCTAssertEqual(sample.minutesRemaining, 99)
    }

    func testACPowerWithoutChargingDoesNotUseEitherTimeEstimate() {
        let description: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSIsChargingKey: false,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
            kIOPSTimeToFullChargeKey: NSNumber(value: 35),
            kIOPSTimeToEmptyKey: NSNumber(value: 99),
        ]
        let sample = PowerSourceDecoder.sample(descriptions: [description])
        XCTAssertTrue(sample.probeSucceeded)
        XCTAssertTrue(sample.hasBattery)
        XCTAssertFalse(sample.isCharging)
        XCTAssertTrue(sample.isPluggedIn)
        XCTAssertNil(sample.minutesRemaining)
    }

    func testMissingOrInvalidBatteryCapacityStaysUnavailable() {
        let capacities: [[String: Any]] = [
            [:],
            [kIOPSCurrentCapacityKey: NSNumber(value: 40)],
            [kIOPSMaxCapacityKey: NSNumber(value: 80)],
            [kIOPSCurrentCapacityKey: NSNumber(value: -1), kIOPSMaxCapacityKey: NSNumber(value: 80)],
            [kIOPSCurrentCapacityKey: NSNumber(value: 40), kIOPSMaxCapacityKey: NSNumber(value: 0)],
        ]
        for var description in capacities {
            description[kIOPSTypeKey] = kIOPSInternalBatteryType
            let sample = PowerSourceDecoder.sample(descriptions: [description])
            XCTAssertTrue(sample.probeSucceeded)
            XCTAssertTrue(sample.hasBattery)
            XCTAssertNil(sample.chargeFraction)
        }
    }

    func testMinusOneBatteryTimeEstimatesStayUnavailable() {
        let states = [
            (charging: true, state: kIOPSACPowerValue),
            (charging: false, state: kIOPSBatteryPowerValue),
        ]
        for (charging, state) in states {
            let description: [String: Any] = [
                kIOPSTypeKey: kIOPSInternalBatteryType,
                kIOPSIsChargingKey: charging,
                kIOPSPowerSourceStateKey: state,
                kIOPSTimeToFullChargeKey: NSNumber(value: charging ? -1 : 35),
                kIOPSTimeToEmptyKey: NSNumber(value: charging ? 99 : -1),
            ]
            let sample = PowerSourceDecoder.sample(descriptions: [description])
            XCTAssertTrue(sample.probeSucceeded)
            XCTAssertTrue(sample.hasBattery)
            XCTAssertNil(sample.minutesRemaining)
        }
    }

    func testNonfiniteBatteryCapacitiesCannotBecomeValidCharge() {
        for value in [Double.nan, .infinity, -.infinity] {
            for key in [kIOPSCurrentCapacityKey, kIOPSMaxCapacityKey] {
                var description: [String: Any] = [
                    kIOPSTypeKey: kIOPSInternalBatteryType,
                    kIOPSCurrentCapacityKey: NSNumber(value: 50),
                    kIOPSMaxCapacityKey: NSNumber(value: 100),
                ]
                description[key] = NSNumber(value: value)
                let sample = PowerSourceDecoder.sample(descriptions: [description])
                XCTAssertTrue(sample.probeSucceeded)
                XCTAssertTrue(sample.hasBattery)
                XCTAssertNil(sample.chargeFraction, "\(key)=\(value)")
            }
        }
    }


    func testSuccessfulPowerReadWithoutInternalBatteryIsSuccessful() {
        let descriptions: [[[String: Any]]] = [
            [],
            [[kIOPSTypeKey: kIOPSUPSType, kIOPSIsPresentKey: true]],
            [[kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSIsPresentKey: false]],
        ]
        for sources in descriptions {
            let sample = PowerSourceDecoder.sample(descriptions: sources)
            XCTAssertTrue(sample.probeSucceeded)
            XCTAssertFalse(sample.hasBattery)
            XCTAssertNil(sample.chargeFraction)
            XCTAssertNil(sample.minutesRemaining)
        }
    }

    func testFailedPowerReadRemainsUnsuccessful() {
        let sample = PowerSourceDecoder.sample(descriptions: nil)
        XCTAssertFalse(sample.probeSucceeded)
        XCTAssertFalse(sample.hasBattery)
        XCTAssertNil(sample.chargeFraction)
        XCTAssertNil(sample.minutesRemaining)
    }

    func testPowerWithoutBatteryDoesNotInventChargeOrTime() {
        let sample = PowerSample()
        XCTAssertFalse(sample.probeSucceeded)
        XCTAssertFalse(sample.hasBattery)
        XCTAssertNil(sample.chargeFraction)
        XCTAssertFalse(sample.isCharging)
        XCTAssertFalse(sample.isPluggedIn)
        XCTAssertNil(sample.minutesRemaining)
    }
}
