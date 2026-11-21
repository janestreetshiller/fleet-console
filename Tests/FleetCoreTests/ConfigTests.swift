import XCTest
@testable import FleetCore

final class ConfigTests: XCTestCase {

    private func decode(_ json: String) throws -> FleetConfig {
        try Codec.decode(FleetConfig.self, from: Data(json.utf8))
    }

    func testEmptyObjectDecodesToDefaults() throws {
        let config = try decode("{}")
        XCTAssertTrue(config.ui.sections.processes)
        XCTAssertTrue(config.ui.sections.network)
        XCTAssertFalse(config.ui.features.allowProcessTermination,
                       "ending processes must be off unless it is asked for")
        XCTAssertNil(config.ui.consoles.network)
        XCTAssertNil(config.ui.consoles.vlan)
    }

    func testPartialUIBlockKeepsSiblingDefaults() throws {
        let config = try decode("""
        {"ui": {"sections": {"processes": false}}}
        """)
        XCTAssertFalse(config.ui.sections.processes)
        XCTAssertTrue(config.ui.sections.services, "an unnamed sibling keeps its default")
        XCTAssertEqual(config.ui.intervals.processSampleSec, 4,
                       "an unnamed sibling block keeps its defaults")
    }

    func testUnknownKeysAreIgnored() throws {
        let config = try decode("""
        {"ui": {"sections": {"quantumTunnel": true}, "somethingFromV3": 12}}
        """)
        XCTAssertTrue(config.ui.sections.services)
    }

    func testIntervalsAreClamped() throws {
        let config = try decode("""
        {"ui": {"intervals": {"networkRefreshSec": 0, "processSampleSec": -5,
                              "routingRefreshSec": 0.001}}}
        """)
        XCTAssertEqual(config.ui.intervals.clampedNetworkRefresh, 5)
        XCTAssertEqual(config.ui.intervals.clampedProcessSample, 2)
    }

    func testGenerousIntervalsAreLeftAlone() throws {
        let config = try decode("""
        {"ui": {"intervals": {"networkRefreshSec": 120, "processSampleSec": 30}}}
        """)
        XCTAssertEqual(config.ui.intervals.clampedNetworkRefresh, 120)
        XCTAssertEqual(config.ui.intervals.clampedProcessSample, 30)
    }

    func testRoundTrip() throws {
        var original = FleetConfig()
        original.ui.features.allowProcessTermination = true
        original.ui.sections.devices = false
        original.ui.consoles.network = "http://10.0.0.1"
        let data = try Codec.prettyEncoder.encode(original)
        let restored = try Codec.decode(FleetConfig.self, from: data)
        XCTAssertTrue(restored.ui.features.allowProcessTermination)
        XCTAssertFalse(restored.ui.sections.devices)
        XCTAssertEqual(restored.ui.consoles.network, "http://10.0.0.1")
    }
}

extension ConfigTests {
    func testSegmentsDefaultToEmpty() throws {
        XCTAssertTrue(try decode("{}").networkSegments.isEmpty,
                      "nothing renders until something is declared")
    }

    func testSegmentDecodesMinimally() throws {
        let config = try decode("""
        {"networkSegments": [{"cidr": "10.10.40.0/24"}]}
        """)
        let segment = try XCTUnwrap(config.networkSegments.first)
        XCTAssertEqual(segment.cidr, "10.10.40.0/24")
        XCTAssertNil(segment.tag, "a segment need not have a tag")
        XCTAssertFalse(segment.name.isEmpty, "a nameless segment would render a blank tag")
    }

    func testSegmentRoundTrips() throws {
        var original = FleetConfig()
        original.networkSegments = [
            .init(tag: 40, name: "Guest", cidr: "10.10.40.0/24",
                  gateway: "10.10.40.1", purpose: "isolated wireless")
        ]
        let restored = try Codec.decode(FleetConfig.self,
                                        from: try Codec.prettyEncoder.encode(original))
        XCTAssertEqual(restored.networkSegments.first?.tag, 40)
        XCTAssertEqual(restored.networkSegments.first?.name, "Guest")
        XCTAssertEqual(restored.networkSegments.first?.gateway, "10.10.40.1")
    }
}
