import Testing
@testable import FleetCore

struct TopologyOptionsTests {
    @Test func flagsHaveExplicitOperands() throws {
        let options = try TopologyOptions(arguments: ["--json", "--owner", "true", "--snapshot", "saved.json"])
        #expect(options.json)
        #expect(options.owner == "true")
        #expect(options.snapshotPath == "saved.json")
    }
    @Test func rejectsIgnoredAndAmbiguousArguments() {
        for arguments in [["--json", "garbage"], ["--", "garbage"], ["--owner"], ["--owner", "--json"],
                          ["--owner", "a", "--owner", "b"], ["--json", "--json"], ["--unknown"]] {
            #expect(throws: (any Error).self) { try TopologyOptions(arguments: arguments) }
        }
    }
}
