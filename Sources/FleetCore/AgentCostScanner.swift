import Foundation

// The IO half of daily spend. Everything that touches the filesystem or a
// database lives here; `AgentCost.swift` stays pure so the pricing can be
// tested from fixtures. See the header there.
//
// This reads other tools' private records, read-only and never in place: a
// transcript is memory-mapped, opencode's database is opened `SQLITE_OPEN_READONLY`,
// and nothing here writes, moves or locks a file belonging to another app. A
// scan that cannot read something reports that as a source, never as a zero.

/// Walks each agent's own usage record and prices today.
///
/// Constructed with an explicit `home` and `calendar` so the whole scan can be
/// pointed at a fixture tree in a test without a process-wide environment
/// change, and so "today" is the operator's local day rather than UTC — spend
/// is something you compare against a daily habit, not a billing period.
public struct AgentCostScanner: Sendable {
    private let home: URL
    private let calendar: Calendar

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                calendar: Calendar = .current) {
        self.home = home
        self.calendar = calendar
    }

    /// Every tool this app knows how to look for, in the order the popover
    /// lists them. A tool absent from the machine still gets a snapshot — the
    /// display layer joins by agent id, so it simply never draws a row.
    public func scan(now: Date = Date()) -> AgentCostTotals {
        let day = day(containing: now)
        return AgentCostTotals(
            snapshots: [
                claude(day: day, now: now),
                codex(day: day, now: now),
                opencode(day: day, now: now),
                AgentCostSnapshot(id: "gemini", amountUSD: nil,
                                  source: .unpublished(tool: "Gemini CLI"), sampledAt: now),
                AgentCostSnapshot(id: "aider", amountUSD: nil,
                                  source: .unpublished(tool: "aider"), sampledAt: now)
            ],
            sampledAt: now)
    }

    /// The operator's local day, half-open. See `AgentCostParser.timestamp`.
    func day(containing now: Date) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    // MARK: - Claude Code

    /// `~/.claude/projects/<project>/<session>.jsonl`, one JSON object per turn.
    private func claude(day: DateInterval, now: Date) -> AgentCostSnapshot {
        let base = home.appending(path: ".claude/projects", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: base.path) else {
            return AgentCostSnapshot(id: "claude", amountUSD: nil,
                                     source: .notInstalled(tool: "Claude Code"), sampledAt: now)
        }
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.isDirectoryKey])
        else {
            return AgentCostSnapshot(id: "claude", amountUSD: nil,
                                     source: .unreadable(path: base.path,
                                                         reason: "directory not readable"),
                                     sampledAt: now)
        }

        var cost = 0.0
        var last: Date?
        var files = 0
        for project in projects {
            for file in transcripts(in: project, touchedSince: day.start) {
                files += 1
                forEachLine(of: file) { line in
                    guard let sample = AgentCostParser.claudeLine(line, in: day) else { return }
                    cost += sample.costUSD
                    last = max(last ?? sample.at, sample.at)
                }
            }
        }
        return AgentCostSnapshot(id: "claude", amountUSD: cost, lastActivityAt: last,
                                 source: .sessionLogs(path: base.path, files: files),
                                 sampledAt: now)
    }

    // MARK: - Codex

    /// `~/.codex/sessions/YYYY/MM/DD/*.jsonl`. Yesterday's directory is scanned
    /// too: a session opened before midnight keeps writing into the directory it
    /// started in, so today's turns land in yesterday's folder. The line-level
    /// timestamp is what actually decides the day — the directory is only a
    /// cheap way to avoid walking the whole archive.
    private func codex(day: DateInterval, now: Date) -> AgentCostSnapshot {
        let base = home.appending(path: ".codex/sessions", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: base.path) else {
            return AgentCostSnapshot(id: "codex", amountUSD: nil,
                                     source: .notInstalled(tool: "Codex"), sampledAt: now)
        }

        var cost = 0.0
        var last: Date?
        var files = 0
        for offset in 0...1 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day
            else { continue }
            let directory = base.appending(
                path: String(format: "%04d/%02d/%02d", year, month, dayOfMonth),
                directoryHint: .isDirectory)
            for file in transcripts(in: directory, touchedSince: day.start) {
                files += 1
                forEachLine(of: file) { line in
                    guard let sample = AgentCostParser.codexLine(line, in: day) else { return }
                    cost += sample.costUSD
                    last = max(last ?? sample.at, sample.at)
                }
            }
        }
        return AgentCostSnapshot(id: "codex", amountUSD: cost, lastActivityAt: last,
                                 source: .sessionLogs(path: base.path, files: files),
                                 sampledAt: now)
    }

    // MARK: - opencode

    /// opencode keeps its own SQLite store and records the cost it was charged,
    /// so this reads rather than prices.
    ///
    /// Masterwork Bar shelled out to the `sqlite3` binary here. We already link
    /// libsqlite3 for the registry and `SQLiteDB` already handles the read-only
    /// open — including the WAL fallback, which matters precisely because the
    /// database being read belongs to a process that may be running right now.
    private func opencode(day: DateInterval, now: Date) -> AgentCostSnapshot {
        let path = home.appending(path: ".local/share/opencode/opencode.db").path
        guard FileManager.default.fileExists(atPath: path) else {
            return AgentCostSnapshot(id: "opencode", amountUSD: nil,
                                     source: .notInstalled(tool: "opencode"), sampledAt: now)
        }

        var cost = 0.0
        var last: Date?
        var rows = 0
        do {
            let db = try SQLiteDB(path: path, readOnly: true)
            // Milliseconds: opencode stamps `time_created` the way JavaScript does.
            let since = Int64(day.start.timeIntervalSince1970 * 1000)
            try db.query("""
                SELECT data FROM message
                WHERE time_created >= ? AND data LIKE '%"role":"assistant"%'
                """, [.int(since)]) { row in
                guard let data = row.text(0),
                      let sample = AgentCostParser.opencodeRow(data) else { return }
                rows += 1
                cost += sample.costUSD
                if sample.at != .distantPast { last = max(last ?? sample.at, sample.at) }
            }
        } catch {
            return AgentCostSnapshot(id: "opencode", amountUSD: nil,
                                     source: .unreadable(path: path,
                                                         reason: shortReason(error)),
                                     sampledAt: now)
        }
        return AgentCostSnapshot(id: "opencode", amountUSD: cost, lastActivityAt: last,
                                 source: .toolDatabase(path: path, rows: rows), sampledAt: now)
    }

    // MARK: - Reading

    /// `.jsonl` files in `directory` whose contents changed on or after `since`.
    ///
    /// The mtime filter is a prefilter and nothing more — a file it lets through
    /// still has every line's timestamp checked. It exists because the archive
    /// grows without bound and re-reading a year of transcripts to price one day
    /// would turn a menu-bar refresh into a stall.
    private func transcripts(in directory: URL, touchedSince since: Date) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }
        return entries.filter { url in
            guard url.pathExtension == "jsonl" else { return false }
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            return (modified ?? .distantPast) >= since
        }
    }

    /// Memory-mapped and split on newlines, so a multi-hundred-megabyte
    /// transcript costs address space rather than resident memory. A file that
    /// will not map, or a line that is not UTF-8, is skipped: one unreadable
    /// transcript must not take the whole day's figure down with it.
    private func forEachLine(of url: URL, _ body: (String) -> Void) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        for slice in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard let line = String(data: Data(slice), encoding: .utf8) else { continue }
            body(line)
        }
    }

    /// The message without the type name, so a row reads as a sentence.
    private func shortReason(_ error: Error) -> String {
        if case FleetError.storage(let message) = error { return message }
        return error.localizedDescription
    }
}
