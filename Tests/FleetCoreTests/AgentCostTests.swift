import XCTest
@testable import FleetCore

final class AgentCostTests: XCTestCase {

    private let day = DateInterval(start: Date(timeIntervalSince1970: 1_787_356_800),
                                   duration: 86_400)

    private func claudeLine(model: String = "claude-sonnet-4-5",
                            timestamp: String = "2026-08-22T10:15:00.000Z",
                            input: Int = 1000, output: Int = 500,
                            cacheRead: Int = 2000, cacheWrite: Int = 100) -> String {
        """
        {"timestamp":"\(timestamp)","message":{"model":"\(model)","usage":\
        {"input_tokens":\(input),"output_tokens":\(output),\
        "cache_read_input_tokens":\(cacheRead),\
        "cache_creation_input_tokens":\(cacheWrite)}}}
        """
    }

    private func codexLine(timestamp: String = "2026-08-22T10:15:00Z",
                           input: Int = 10000, cached: Int = 8000,
                           output: Int = 500) -> String {
        """
        {"timestamp":"\(timestamp)","payload":{"type":"token_count","info":\
        {"last_token_usage":{"input_tokens":\(input),\
        "cached_input_tokens":\(cached),"output_tokens":\(output)}}}}
        """
    }

    func testClaudePricesEveryTokenClass() {
        let sample = AgentCostParser.claudeLine(claudeLine(), in: day)
        XCTAssertEqual(sample?.costUSD ?? -1, 0.011475, accuracy: 1e-9)
    }

    func testClaudeReadsTheFlatTranscriptShape() {
        let flat = """
        {"timestamp":"2026-08-22T10:15:00.000Z","model":"claude-sonnet-4-5",\
        "usage":{"input_tokens":1000,"output_tokens":500,\
        "cache_read_input_tokens":2000,"cache_creation_input_tokens":100}}
        """
        let nested = AgentCostParser.claudeLine(claudeLine(), in: day)
        let top = AgentCostParser.claudeLine(flat, in: day)
        XCTAssertEqual(top?.costUSD ?? -1, nested?.costUSD ?? -2, accuracy: 1e-12)
    }

    func testClaudePicksTheModelFamilyRate() {
        let opus = AgentCostParser.claudeLine(
            claudeLine(model: "claude-opus-4-1", input: 1_000_000, output: 0,
                       cacheRead: 0, cacheWrite: 0), in: day)
        let haiku = AgentCostParser.claudeLine(
            claudeLine(model: "claude-haiku-4-5", input: 1_000_000, output: 0,
                       cacheRead: 0, cacheWrite: 0), in: day)
        XCTAssertEqual(opus?.costUSD ?? -1, 15.0, accuracy: 1e-9)
        XCTAssertEqual(haiku?.costUSD ?? -1, 0.80, accuracy: 1e-9)
    }

    func testUnknownClaudeModelFallsBackToSonnetRatherThanZero() {
        let sample = AgentCostParser.claudeLine(
            claudeLine(model: "claude-something-6", input: 1_000_000, output: 0,
                       cacheRead: 0, cacheWrite: 0), in: day)
        XCTAssertEqual(sample?.costUSD ?? -1, 3.0, accuracy: 1e-9)
    }

    func testSyntheticModelsAreNotPriced() {
        let sample = AgentCostParser.claudeLine(
            claudeLine(model: "<synthetic>"), in: day)
        XCTAssertNil(sample)
    }

    func testLineWithoutUsageIsSkipped() {
        let line = """
        {"timestamp":"2026-08-22T10:15:00.000Z","type":"summary","text":"hello"}
        """
        XCTAssertNil(AgentCostParser.claudeLine(line, in: day))
    }

    func testMalformedJSONIsSkippedRatherThanThrowing() {
        let line = #"{"timestamp":"2026-08-22T10:15:00Z","usage":{"input_tokens":"#
        XCTAssertNil(AgentCostParser.claudeLine(line, in: day))
    }

    func testTimestampsOutsideTheDayAreSkipped() {
        XCTAssertNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-21T23:59:59.000Z"), in: day))
        XCTAssertNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-23T00:00:01.000Z"), in: day))
    }

    func testMidnightBelongsToTheDayItStarts() {
        XCTAssertNotNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-22T00:00:00.000Z"), in: day))
        XCTAssertNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-23T00:00:00.000Z"), in: day))
    }

    func testTimestampsParseWithAndWithoutFractionalSeconds() {
        XCTAssertNotNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-22T10:15:00.123Z"), in: day))
        XCTAssertNotNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-22T10:15:00Z"), in: day))
    }

    func testOffsetTimestampsArePricedAsInstants() {
        XCTAssertNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-22T01:00:00+02:00"), in: day))
        XCTAssertNotNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-22T02:00:00+02:00"), in: day))
    }

    func testCodexSubtractsCachedInputFromTotalInput() {
        let sample = AgentCostParser.codexLine(codexLine(), in: day)
        XCTAssertEqual(sample?.costUSD ?? -1, 0.0085, accuracy: 1e-9)
    }

    func testCodexNeverPricesNegativeFreshInput() {
        let sample = AgentCostParser.codexLine(
            codexLine(input: 100, cached: 5000, output: 0), in: day)
        XCTAssertEqual(sample?.costUSD ?? -1, 5000 * 0.125 / 1_000_000, accuracy: 1e-12)
    }

    func testCodexLineWithoutTokenCountIsSkipped() {
        let line = """
        {"timestamp":"2026-08-22T10:15:00Z","payload":{"type":"message"}}
        """
        XCTAssertNil(AgentCostParser.codexLine(line, in: day))
    }

    func testOpencodeUsesTheToolsOwnFigure() {
        let row = #"{"role":"assistant","cost":0.0421,"time":{"created":1787400000000}}"#
        let sample = AgentCostParser.opencodeRow(row)
        XCTAssertEqual(sample?.costUSD ?? -1, 0.0421, accuracy: 1e-12)
        XCTAssertEqual(sample?.at.timeIntervalSince1970 ?? 0, 1_787_400_000, accuracy: 1)
    }

    func testOpencodeRowWithoutCostIsSkipped() {
        XCTAssertNil(AgentCostParser.opencodeRow(#"{"role":"assistant"}"#))
    }

    func testOpencodeRowWithoutTimeStillCarriesItsCost() {
        let sample = AgentCostParser.opencodeRow(#"{"cost":0.5}"#)
        XCTAssertEqual(sample?.costUSD ?? -1, 0.5, accuracy: 1e-12)
        XCTAssertEqual(sample?.at, .distantPast)
    }

    private func totals(_ snapshots: [AgentCostSnapshot]) -> AgentCostTotals {
        AgentCostTotals(snapshots: snapshots, sampledAt: day.start)
    }

    func testUnknownsAreExcludedFromTheTotalRatherThanCountedAsZero() {
        let rollup = totals([
            AgentCostSnapshot(id: "claude", amountUSD: 4.00,
                              source: .sessionLogs(path: "/p", files: 3), sampledAt: day.start),
            AgentCostSnapshot(id: "gemini", amountUSD: nil,
                              source: .unpublished(tool: "Gemini CLI"), sampledAt: day.start),
            AgentCostSnapshot(id: "aider", amountUSD: nil,
                              source: .unpublished(tool: "aider"), sampledAt: day.start)
        ])
        XCTAssertEqual(rollup.knownTotalUSD, 4.00, accuracy: 1e-12)
        XCTAssertEqual(rollup.unknownCount, 2)
    }

    func testAPricedZeroIsNotAnUnknown() {
        let priced = AgentCostSnapshot(id: "claude", amountUSD: 0,
                                       source: .sessionLogs(path: "/p", files: 0),
                                       sampledAt: day.start)
        let unknown = AgentCostSnapshot(id: "aider", amountUSD: nil,
                                        source: .unpublished(tool: "aider"),
                                        sampledAt: day.start)
        XCTAssertTrue(priced.isKnown)
        XCTAssertFalse(unknown.isKnown)
        XCTAssertEqual(totals([priced, unknown]).unknownCount, 1)
    }

    func testOnlyUnreadableRecordsCountAsFaults() {
        let rollup = totals([
            AgentCostSnapshot(id: "gemini", amountUSD: nil,
                              source: .unpublished(tool: "Gemini CLI"), sampledAt: day.start),
            AgentCostSnapshot(id: "claude", amountUSD: nil,
                              source: .unreadable(path: "~/.claude/projects",
                                                  reason: "permission denied"),
                              sampledAt: day.start)
        ])
        XCTAssertEqual(rollup.faults.map(\.id), ["claude"])
        XCTAssertEqual(rollup.unknownCount, 2)
        XCTAssertTrue(rollup.snapshot(for: "claude")?.source.isFault ?? false)
        XCTAssertFalse(rollup.snapshot(for: "gemini")?.source.isFault ?? true)
    }

    func testSourceExplanationsSingulariseTheirCounts() {
        XCTAssertEqual(AgentCostSource.sessionLogs(path: "/p", files: 1).explanation,
                       "1 session today")
        XCTAssertEqual(AgentCostSource.sessionLogs(path: "/p", files: 4).explanation,
                       "4 sessions today")
        XCTAssertEqual(AgentCostSource.toolDatabase(path: "/p", rows: 1).explanation,
                       "1 message today")
    }

    func testSnapshotSurvivesACodableRoundTrip() throws {
        let original = totals([
            AgentCostSnapshot(id: "claude", amountUSD: 1.25,
                              lastActivityAt: day.start,
                              source: .sessionLogs(path: "/p", files: 2), sampledAt: day.start),
            AgentCostSnapshot(id: "aider", amountUSD: nil,
                              source: .unpublished(tool: "aider"), sampledAt: day.start)
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentCostTotals.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.snapshot(for: "aider")?.amountUSD)
    }
}
