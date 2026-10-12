import XCTest
@testable import FleetCore

final class ServiceLabelsTests: XCTestCase {
    func testDecodedBlankNameUsesRecordedName() throws {
        let data = Data("{\"name\":\"  \"}".utf8)
        let label = try JSONDecoder().decode(ServiceLabel.self, from: data)
        XCTAssertEqual(label.displayName(fallback: "worker-api"), "worker-api")
    }
    func testBlankFriendlyNameUsesRecordedName() {
        let label = ServiceLabel(name: " \n\t ")
        XCTAssertNil(label.name)
        XCTAssertEqual(label.displayName(fallback: "worker-api"), "worker-api")
    }

    func testColorTagSurvivesJSONRoundTrip() throws {
        for color in ["blue", "purple", "teal", "orange", "pink", "gray"] {
            let data = Data("{\"name\":\"Local API\",\"color\":\"\(color)\"}".utf8)
            let label = try JSONDecoder().decode(ServiceLabel.self, from: data)
            let encoded = try JSONEncoder().encode(label)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: String])
            XCTAssertEqual(object["color"], color)
            XCTAssertEqual(label.displayName(fallback: "worker-api"), "Local API")
        }
    }
}
