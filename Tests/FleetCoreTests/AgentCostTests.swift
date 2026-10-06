import XCTest
@testable import FleetCore

/// Spend is money on a screen, and two mistakes in here are worse than showing
/// nothing at all: pricing a turn that was never billed, and reporting an agent
/// we cannot price as having cost zero. Both are tested directly, from fixture
/// lines in the on-disk shapes this machine actually has, with the day injected
/// so nothing here depends on the timezone the suite happens to run in.
///
/// These are the read-only fixture tests the merge recommendation asks for
/// *before* the parser moves — every expected figure below was computed by hand
/// from the published rates, not by running the code.
final class AgentCostTests: XCTestCase {

    /// 2026-08-22 00:00:00Z, one day long. Fixed epoch rather than a calendar
    /// computation, so the fixture and the assertion cannot drift together.
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

    // MARK: - Claude

    /// 1000 input @ $3 + 500 output @ $15 + 2000 cache reads @ $0.30 +
    /// 100 cache writes @ $3.75, per million = $0.011475.
    func testClaudePricesEveryTokenClass() {
        let sample = AgentCostParser.claudeLine(claudeLine(), in: day)
        XCTAssertEqual(sample?.costUSD ?? -1, 0.011475, accuracy: 1e-9)
    }

    /// The older transcript generation put usage and model at the top level.
    /// Both shapes are still on disk, so both have to price identically.
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

    /// An unrecognised model prices as Sonnet, not as free. A future model
    /// silently costing nothing is the failure that makes the whole figure
    /// untrustworthy without ever looking wrong.
    func testUnknownClaudeModelFallsBackToSonnetRatherThanZero() {
        let sample = AgentCostParser.claudeLine(
            claudeLine(model: "claude-something-6", input: 1_000_000, output: 0,
                       cacheRead: 0, cacheWrite: 0), in: day)
        XCTAssertEqual(sample?.costUSD ?? -1, 3.0, accuracy: 1e-9)
    }

    /// Synthetic turns are replayed locally and never billed. Pricing them
    /// invents spend that no invoice will ever show.
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

    // MARK: - The day boundary

    func testTimestampsOutsideTheDayAreSkipped() {
        XCTAssertNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-21T23:59:59.000Z"), in: day))
        XCTAssertNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-23T00:00:01.000Z"), in: day))
    }

    /// The interval is half-open. `DateInterval.contains` includes its end, and
    /// a turn stamped exactly at midnight would then be billed to both days.
    func testMidnightBelongsToTheDayItStarts() {
        XCTAssertNotNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-22T00:00:00.000Z"), in: day))
        XCTAssertNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-23T00:00:00.000Z"), in: day))
    }

    /// Both RFC 3339 spellings appear in the same directory.
    func testTimestampsParseWithAndWithoutFractionalSeconds() {
        XCTAssertNotNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-22T10:15:00.123Z"), in: day))
        XCTAssertNotNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-22T10:15:00Z"), in: day))
    }

    /// An offset timestamp is an instant, not a wall clock: 01:00+02:00 is
    /// 23:00 the previous day in UTC and belongs to the previous day's bill.
    func testOffsetTimestampsArePricedAsInstants() {
        XCTAssertNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-22T01:00:00+02:00"), in: day))
        XCTAssertNotNil(AgentCostParser.claudeLine(
            claudeLine(timestamp: "2026-08-22T02:00:00+02:00"), in: day))
    }

    // MARK: - Codex

    /// Codex's `input_tokens` includes `cached_input_tokens`, so the cached
    /// share is priced once at the cache rate and not twice:
    /// 2000 fresh @ $1.25 + 8000 cached @ $0.125 + 500 output @ $10 = $0.0085.
    func testCodexSubtractsCachedInputFromTotalInput() {
        let sample = AgentCostParser.codexLine(codexLine(), in: day)
        XCTAssertEqual(sample?.costUSD ?? -1, 0.0085, accuracy: 1e-9)
    }

    /// A line claiming more cached input than input at all would otherwise
    /// price negatively and quietly reduce the day's total.
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

    // MARK: - opencode

    /// opencode records the cost it was charged. We read it and price nothing.
    func testOpencodeUsesTheToolsOwnFigure() {
        let row = #"{"role":"assistant","cost":0.0421,"time":{"created":1787400000000}}"#
        let sample = AgentCostParser.opencodeRow(row)
        XCTAssertEqual(sample?.costUSD ?? -1, 0.0421, accuracy: 1e-12)
        XCTAssertEqual(sample?.at.timeIntervalSince1970 ?? 0, 1_787_400_000, accuracy: 1)
    }

    func testOpencodeRowWithoutCostIsSkipped() {
        XCTAssertNil(AgentCostParser.opencodeRow(#"{"role":"assistant"}"#))
    }

    /// A row with no creation time still carries its cost; it just loses every
    /// `max` for last-activity, which is the same outcome as skipping it.
    func testOpencodeRowWithoutTimeStillCarriesItsCost() {
        let sample = AgentCostParser.opencodeRow(#"{"cost":0.5}"#)
        XCTAssertEqual(sample?.costUSD ?? -1, 0.5, accuracy: 1e-12)
        XCTAssertEqual(sample?.at, .distantPast)
    }

    // MARK: - Honest unknowns

    private func totals(_ snapshots: [AgentCostSnapshot]) -> AgentCostTotals {
        AgentCostTotals(snapshots: snapshots, sampledAt: day.start)
    }

    /// The whole reason `amountUSD` is optional: an agent we cannot price is
    /// left out of the sum rather than added as zero, and the count is what
    /// keeps the remaining total from reading as the day's whole spend.
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

    /// A priced zero and an unknown are different claims. An agent that ran
    /// and cost nothing is knowable; one with no usage record is not.
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

    /// Only a record that should have been readable counts as a fault. A tool
    /// that publishes nothing is a permanent absence and must not raise an
    /// alarm every refresh forever.
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

    /// The snapshot rides the socket to the app, so it has to survive a round
    /// trip — including the `nil` that carries the unknown.
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
