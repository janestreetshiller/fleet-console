import Foundation

public struct AgentCostScanner: Sendable {
    private let home: URL
    private let calendar: Calendar

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                calendar: Calendar = .current) {
        self.home = home
        self.calendar = calendar
    }

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

    func day(containing now: Date) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

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

    private func forEachLine(of url: URL, _ body: (String) -> Void) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        for slice in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard let line = String(data: Data(slice), encoding: .utf8) else { continue }
            body(line)
        }
    }

    private func shortReason(_ error: Error) -> String {
        if case FleetError.storage(let message) = error { return message }
        return error.localizedDescription
    }
}
