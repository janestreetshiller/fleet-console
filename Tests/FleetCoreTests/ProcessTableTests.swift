import XCTest
@testable import FleetCore

final class ProcessTableTests: XCTestCase {

    func testParsesTheLiveProcessTable() throws {
        let table = try XCTUnwrap(ProcessTable.readProcesses(),
                                  "ps did not run to completion")
        XCTAssertFalse(table.isEmpty)

        let launchd = try XCTUnwrap(table[1], "pid 1 was not in the table")
        XCTAssertEqual(launchd.commandLine.contains("/sbin/launchd"), true,
                       "command column shifted: got \(launchd.commandLine)")
        XCTAssertEqual(launchd.uid, 0)
        XCTAssertFalse(launchd.state.isEmpty, "state column is empty")
        XCTAssertTrue(launchd.state.allSatisfy { $0.isLetter || $0 == "+" || $0 == "<" || $0 == ">" },
                      "state should be BSD letters and modifiers, got \(launchd.state)")
    }

    func testStartSignatureLooksLikeADate() throws {
        let table = try XCTUnwrap(ProcessTable.readProcesses())
        let launchd = try XCTUnwrap(table[1])
        let tokens = launchd.startSignature.split(separator: " ")
        XCTAssertEqual(tokens.count, 5,
                       "expected 5 lstart tokens, got \(launchd.startSignature)")
        XCTAssertNotNil(Int(tokens[4]), "last lstart token should be a year, got \(tokens[4])")
    }

    func testStateModifiersDoNotChangeTheReading() throws {
        let table = try XCTUnwrap(ProcessTable.readProcesses())
        let withModifiers = table.values.filter { $0.state.count > 1 }
        XCTAssertFalse(withModifiers.isEmpty,
                       "expected at least one process with a state modifier (Ss, S+, …)")
    }
}
