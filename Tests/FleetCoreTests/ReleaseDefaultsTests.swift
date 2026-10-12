import Foundation
import XCTest
@testable import FleetCore

final class ReleaseDefaultsTests: XCTestCase {
    func testFreshConfigurationsHaveAnExplicitEmptyKnownServiceInventory() {
        XCTAssertTrue(FleetConfig().knownServices.isEmpty)
        XCTAssertTrue(FleetConfig.makeDefault(selfHostName: "Fixture Mac", selfTailscaleName: nil).knownServices.isEmpty)
    }

    func testOldConfigurationsOmittingInventoryUseTheEmptyDefault() throws {
        let config = try JSONDecoder().decode(FleetConfig.self, from: Data("{}".utf8))
        XCTAssertTrue(config.knownServices.isEmpty)
    }

    func testExplicitKnownServicesRemainCompatible() throws {
        let config = FleetConfig(knownServices: [.init(id: "fixture", name: "Fixture service", match: "fixture-api", ports: [8787])])
        let decoded = try JSONDecoder().decode(FleetConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded.knownServices.map(\.id), ["fixture"])
    }
}
