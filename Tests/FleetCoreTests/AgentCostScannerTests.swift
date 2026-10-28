import XCTest
@testable import FleetCore

/// The scanner against a fixture home tree: real directories, real `.jsonl`
/// files, real mtimes — but nowhere near the operator's own transcripts, and
/// with `now` and the calendar injected so the day under test is fixed.
///
/// The pricing itself is covered by `AgentCostTests`; what is being checked
/// here is the part that only breaks on a real filesystem — which directories
/// get walked, what a missing tool reports, and that an unreadable record comes
/// back as unknown rather than as zero spend.
final class AgentCostScannerTests: XCTestCase {

    /// 2026-08-22 11:00:00Z, inside the day the fixtures are stamped for.
    private let now = Date(timeIntervalSince1970: 1_787_396_400)
    private var dayStart: Date { Date(timeIntervalSince1970: 1_787_356_800) }
    private var home: URL!

    /// UTC, so the fixture timestamps and the scanner's idea of "today" agree
    /// wherever the suite runs.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "fleetconsole-cost-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
        try super.tearDownWithError()
    }

    private func scanner() -> AgentCostScanner {
        AgentCostScanner(home: home, calendar: utc)
    }

    /// Writes `lines` as a `.jsonl` under `path`, stamped inside the day so the
    /// scanner's mtime prefilter lets it through.
    private func write(_ lines: [String], to path: String) throws {
        let file = home.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: dayStart.addingTimeInterval(3600)],
                                              ofItemAtPath: file.path)
    }

    private func claudeTurn(_ timestamp: String, input: Int, output: Int) -> String {
        """
        {"timestamp":"\(timestamp)","message":{"model":"claude-sonnet-4-5",\
        "usage":{"input_tokens":\(input),"output_tokens":\(output)}}}
        """
    }

    // MARK: - Nothing installed

    /// An empty home is not a free day. Every tool comes back unknown, the
    /// total covers nothing, and none of it is a fault.
    func testAnEmptyHomeReportsUnknownRatherThanZero() {
        let totals = scanner().scan(now: now)
        XCTAssertEqual(totals.snapshots.count, 5)
        XCTAssertTrue(totals.snapshots.allSatisfy { !$0.isKnown })
        XCTAssertEqual(totals.unknownCount, 5)
        XCTAssertEqual(totals.knownTotalUSD, 0, accuracy: 1e-12)
        XCTAssertTrue(totals.faults.isEmpty, "a tool that is not installed is not a fault")
    }

    func testMissingToolsReportNotInstalled() {
        let totals = scanner().scan(now: now)
        guard case .notInstalled = totals.snapshot(for: "claude")?.source else {
            return XCTFail("claude should report not-installed on an empty home")
        }
        guard case .notInstalled = totals.snapshot(for: "opencode")?.source else {
            return XCTFail("opencode should report not-installed on an empty home")
        }
    }

    // MARK: - Claude

    /// 1M input @ $3 plus 1M output @ $15, across two projects, is $18.
    func testClaudeSumsEveryProjectAndSession() throws {
        try write([claudeTurn("2026-08-22T09:00:00.000Z", input: 1_000_000, output: 0)],
                  to: ".claude/projects/alpha/one.jsonl")
        try write([claudeTurn("2026-08-22T10:00:00.000Z", input: 0, output: 1_000_000)],
                  to: ".claude/projects/beta/two.jsonl")

        let snapshot = scanner().scan(now: now).snapshot(for: "claude")
        XCTAssertEqual(snapshot?.amountUSD ?? -1, 18.0, accuracy: 1e-9)
        guard case .sessionLogs(_, let files) = snapshot?.source else {
            return XCTFail("a scanned tool reports session logs")
        }
        XCTAssertEqual(files, 2)
    }

    /// Turns from another day sit in the same file as today's. The day filter
    /// is per line, so the file counts and the spend does not.
    func testClaudeIgnoresYesterdaysTurnsInsideTodaysFile() throws {
        try write([
            claudeTurn("2026-08-21T09:00:00.000Z", input: 1_000_000, output: 0),
            claudeTurn("2026-08-22T09:00:00.000Z", input: 1_000_000, output: 0)
        ], to: ".claude/projects/alpha/one.jsonl")

        let snapshot = scanner().scan(now: now).snapshot(for: "claude")
        XCTAssertEqual(snapshot?.amountUSD ?? -1, 3.0, accuracy: 1e-9)
        XCTAssertEqual(snapshot?.lastActivityAt?.timeIntervalSince1970 ?? 0,
                       1_787_389_200, accuracy: 1, "last activity is today's turn, not yesterday's")
    }

    /// An installed tool that has not run today has genuinely spent nothing.
    /// That is a knowable zero, and it must not read as an unknown.
    func testAnInstalledToolWithNoActivityIsAKnownZero() throws {
        try FileManager.default.createDirectory(
            at: home.appending(path: ".claude/projects"), withIntermediateDirectories: true)
        let snapshot = scanner().scan(now: now).snapshot(for: "claude")
        XCTAssertEqual(snapshot?.amountUSD ?? -1, 0, accuracy: 1e-12)
        XCTAssertTrue(snapshot?.isKnown ?? false)
    }

    /// A file last touched before midnight cannot hold today's turns, and is
    /// skipped without being opened.
    func testTranscriptsUntouchedTodayAreNotRead() throws {
        try write([claudeTurn("2026-08-22T09:00:00.000Z", input: 1_000_000, output: 0)],
                  to: ".claude/projects/alpha/stale.jsonl")
        let stale = home.appending(path: ".claude/projects/alpha/stale.jsonl")
        try FileManager.default.setAttributes(
            [.modificationDate: dayStart.addingTimeInterval(-3600)], ofItemAtPath: stale.path)

        let snapshot = scanner().scan(now: now).snapshot(for: "claude")
        XCTAssertEqual(snapshot?.amountUSD ?? -1, 0, accuracy: 1e-12)
        guard case .sessionLogs(_, let files) = snapshot?.source else {
            return XCTFail("still a scanned tool")
        }
        XCTAssertEqual(files, 0)
    }

    /// Only `.jsonl` is a transcript. A sibling file must not be counted as one.
    func testNonTranscriptFilesAreIgnored() throws {
        try write([claudeTurn("2026-08-22T09:00:00.000Z", input: 1_000_000, output: 0)],
                  to: ".claude/projects/alpha/notes.txt")
        let snapshot = scanner().scan(now: now).snapshot(for: "claude")
        XCTAssertEqual(snapshot?.amountUSD ?? -1, 0, accuracy: 1e-12)
    }

    // MARK: - Codex

    /// A session opened before midnight keeps writing into the directory it
    /// started in, so today's turns land in yesterday's folder. Missing that is
    /// how a morning's spend disappears.
    func testCodexFindsTodaysTurnsInYesterdaysDirectory() throws {
        let turn = """
        {"timestamp":"2026-08-22T00:30:00Z","payload":{"type":"token_count","info":\
        {"last_token_usage":{"input_tokens":1000000,"cached_input_tokens":0,\
        "output_tokens":0}}}}
        """
        try write([turn], to: ".codex/sessions/2026/08/21/overnight.jsonl")

        let snapshot = scanner().scan(now: now).snapshot(for: "codex")
        XCTAssertEqual(snapshot?.amountUSD ?? -1, 1.25, accuracy: 1e-9)
    }

    /// Two days back is not scanned — that is the boundary the directory walk
    /// draws, and a turn there would already have been billed to its own day.
    func testCodexDoesNotWalkTheWholeArchive() throws {
        let turn = """
        {"timestamp":"2026-08-22T00:30:00Z","payload":{"type":"token_count","info":\
        {"last_token_usage":{"input_tokens":1000000,"cached_input_tokens":0,\
        "output_tokens":0}}}}
        """
        try write([turn], to: ".codex/sessions/2026/08/20/ancient.jsonl")

        let snapshot = scanner().scan(now: now).snapshot(for: "codex")
        XCTAssertEqual(snapshot?.amountUSD ?? -1, 0, accuracy: 1e-12)
    }

    // MARK: - opencode

    /// A file that is not a database is the shape of a real failure — a partial
    /// write, a different format after an upgrade. It has to come back as a
    /// fault, not as a day on which opencode was free.
    func testAnUnreadableDatabaseIsAFaultNotAZero() throws {
        let db = home.appending(path: ".local/share/opencode/opencode.db")
        try FileManager.default.createDirectory(at: db.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("this is not a database".utf8).write(to: db)

        let totals = scanner().scan(now: now)
        let snapshot = totals.snapshot(for: "opencode")
        XCTAssertFalse(snapshot?.isKnown ?? true)
        XCTAssertEqual(totals.faults.map(\.id), ["opencode"])
    }

    // MARK: - The rollup

    /// The headline figure: what is knowable is summed, what is not is counted,
    /// and the two are never mixed.
    func testTotalsSumOnlyWhatWasPriced() throws {
        try write([claudeTurn("2026-08-22T09:00:00.000Z", input: 1_000_000, output: 0)],
                  to: ".claude/projects/alpha/one.jsonl")

        let totals = scanner().scan(now: now)
        XCTAssertEqual(totals.knownTotalUSD, 3.0, accuracy: 1e-9)
        XCTAssertEqual(totals.unknownCount, 4, "codex, opencode, gemini and aider are unknown")
        XCTAssertEqual(totals.sampledAt, now)
    }
}
