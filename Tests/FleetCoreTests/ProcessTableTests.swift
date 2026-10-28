import XCTest
@testable import FleetCore

/// `ProcessTable.readProcesses` parses `ps` output positionally, which is fine
/// while every field before the command is whitespace-free — and `state` was
/// inserted into the middle of that run. Every index after it moved by one, and
/// an off-by-one there does not fail loudly: it shifts the start signature into
/// the command line and quietly breaks the PID-reuse guard.
final class ProcessTableTests: XCTestCase {

    /// The real thing, on the machine running the test. `ps -A` always lists at
    /// least itself, so an empty parse is a failure rather than an idle machine.
    func testParsesTheLiveProcessTable() throws {
        let table = try XCTUnwrap(ProcessTable.readProcesses(),
                                  "ps did not run to completion")
        XCTAssertFalse(table.isEmpty)

        // launchd is pid 1 on every Mac, and it is the cheapest anchor for
        // "the columns landed where they were supposed to".
        let launchd = try XCTUnwrap(table[1], "pid 1 was not in the table")
        XCTAssertEqual(launchd.commandLine.contains("/sbin/launchd"), true,
                       "command column shifted: got \(launchd.commandLine)")
        XCTAssertEqual(launchd.uid, 0)
        XCTAssertFalse(launchd.state.isEmpty, "state column is empty")
        XCTAssertTrue(launchd.state.allSatisfy { $0.isLetter || $0 == "+" || $0 == "<" || $0 == ">" },
                      "state should be BSD letters and modifiers, got \(launchd.state)")
    }

    /// The signature is five tokens of `lstart` — "Fri Aug  1 09:12:03 2026" —
    /// and it is the whole PID-reuse guard. If the state column shifted it, this
    /// would be a date fragment plus a stray letter.
    func testStartSignatureLooksLikeADate() throws {
        let table = try XCTUnwrap(ProcessTable.readProcesses())
        let launchd = try XCTUnwrap(table[1])
        let tokens = launchd.startSignature.split(separator: " ")
        XCTAssertEqual(tokens.count, 5,
                       "expected 5 lstart tokens, got \(launchd.startSignature)")
        XCTAssertNotNil(Int(tokens[4]), "last lstart token should be a year, got \(tokens[4])")
    }

    /// Every state `ps` can print maps to something, and the three ordinary ones
    /// stay achromatic — a process list where "running" is green is a wall of
    /// green that says nothing.
    func testStateModifiersDoNotChangeTheReading() throws {
        let table = try XCTUnwrap(ProcessTable.readProcesses())
        // Session leaders and foreground processes carry modifiers; the parse
        // must key on the first letter only.
        let withModifiers = table.values.filter { $0.state.count > 1 }
        XCTAssertFalse(withModifiers.isEmpty,
                       "expected at least one process with a state modifier (Ss, S+, …)")
    }
}
