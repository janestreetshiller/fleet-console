import Foundation
import FleetCore

/// Detects the coding agents you are actually running, and collects host metrics.
///
/// These two things previously lived in separate menu-bar apps: agent sessions in
/// Agent Menubar, host CPU/RAM/SSD in the AI-Pocket SwiftBar plugin. Both are
/// "pertinent info" that belongs in the two FleetConsole menus, so both are
/// gathered here.
enum SessionScanner {

    struct Tool {
        let name: String
        let symbol: String
        /// Matched against the executable name, then the full command line.
        let executables: [String]
        let patterns: [String]
    }

    static let tools: [Tool] = [
        Tool(name: "Claude Code", symbol: "sparkle",
             executables: ["claude"], patterns: ["claude-code", "/claude "]),
        Tool(name: "Codex", symbol: "chevron.left.forwardslash.chevron.right",
             executables: ["codex"], patterns: ["codex-cli", "/codex "]),
        Tool(name: "Gemini CLI", symbol: "diamond",
             executables: ["gemini"], patterns: ["gemini-cli", "/gemini "]),
        Tool(name: "opencode", symbol: "chevron.left.slash.chevron.right",
             executables: ["opencode"], patterns: ["opencode"]),
        Tool(name: "aider", symbol: "pencil.and.outline",
             executables: ["aider"], patterns: ["aider"]),
        Tool(name: "Grok", symbol: "bolt", executables: ["grok"], patterns: ["grok-cli"]),
        Tool(name: "Qwen", symbol: "q.circle", executables: ["qwen"], patterns: ["qwen-code"]),
    ]

    /// One pass over the process table; no extra subprocesses except a single
    /// `lsof` for the working directories of the sessions actually found.
    static func scan(table: ProcessTable, uid: uid_t = geteuid()) -> [AgentSession] {
        var sessions: [AgentSession] = []

        for proc in table.byPID.values {
            guard proc.uid == uid else { continue }
            let executable = proc.executableName.lowercased()
            let line = proc.commandLine.lowercased()

            // The desktop apps ship binaries with the same names as their CLIs
            // ("claude" inside Claude.app, Codex helpers inside ChatGPT.app). A GUI
            // app is not a coding session, and counting its four helper processes
            // as four sessions is worse than not detecting it at all.
            if line.contains(".app/contents/") { continue }
            if line.contains("(renderer)") || line.contains("(service)")
                || line.contains("helper") { continue }

            guard let tool = tools.first(where: { candidate in
                candidate.executables.contains(executable)
                    || candidate.patterns.contains(where: { line.contains($0) })
            }) else { continue }

            // A tool's own helper processes share its name; keep the group leader
            // so one session is one row.
            if proc.pid != proc.pgid, table.process(proc.pgid) != nil { continue }

            sessions.append(AgentSession(
                id: "\(tool.name):\(proc.pid)",
                tool: tool.name,
                symbol: tool.symbol,
                pid: proc.pid,
                project: nil,
                startedAt: Reconciler.parseStartTime(proc.startSignature),
                cpuPct: proc.cpuPct,
                memMB: proc.rssKB / 1024,
                commandLine: String(proc.commandLine.prefix(300))))
        }

        // Working directory = the project being worked on. One lsof call for all.
        if !sessions.isEmpty {
            let cwds = workingDirectories(for: sessions.map(\.pid))
            for index in sessions.indices {
                sessions[index].project = cwds[sessions[index].pid]
            }
        }
        return sessions.sorted { ($0.tool, $0.pid) < ($1.tool, $1.pid) }
    }

    static func workingDirectories(for pids: [Int32]) -> [Int32: String] {
        guard let lsof = Shell.which("lsof", candidates: ["/usr/sbin/lsof", "/usr/bin/lsof"]),
              !pids.isEmpty else { return [:] }
        let result = Shell.run(lsof, ["-a", "-d", "cwd", "-p", pids.map(String.init).joined(separator: ","),
                                      "-F", "pn"], timeout: 8)
        var directories: [Int32: String] = [:]
        var current: Int32 = 0
        for raw in result.stdout.split(separator: "\n") {
            guard let tag = raw.first else { continue }
            let value = String(raw.dropFirst())
            if tag == "p" { current = Int32(value) ?? 0 }
            else if tag == "n", current != 0 { directories[current] = value }
        }
        return directories
    }

    // MARK: - Host metrics

    /// CPU, memory and whole-container SSD usage for this machine. Uses the APFS
    /// container rather than `df /`, which understates a Mac's real disk usage.
    static func localMetrics() -> HostMetrics {
        var metrics = HostMetrics(collectedAt: Date())

        let top = Shell.run("/usr/bin/top", ["-l", "1", "-s", "0", "-n", "0"], timeout: 8).stdout
        if let line = top.split(separator: "\n").first(where: { $0.contains("CPU usage") }) {
            let numbers = line.split(whereSeparator: { !"0123456789.".contains($0) })
                .compactMap { Double($0) }
            if numbers.count >= 2 { metrics.cpuPct = (numbers[0] + numbers[1]).rounded() }
        }
        if let line = top.split(separator: "\n").first(where: { $0.hasPrefix("PhysMem") }) {
            let used = line.split(separator: " ").first { $0.hasSuffix("G") || $0.hasSuffix("M") }
            if let used {
                let value = Double(used.dropLast()) ?? 0
                metrics.memUsedGB = used.hasSuffix("M") ? value / 1024 : value
            }
        }
        let totalBytes = Shell.run("/usr/sbin/sysctl", ["-n", "hw.memsize"], timeout: 4).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let bytes = Double(totalBytes) { metrics.memTotalGB = bytes / 1_073_741_824 }

        // The whole APFS container, not `df /` — a Mac's root volume understates
        // real usage badly because of firmlinks and snapshots.
        // diskutil indents with "|   ", so the pipes must be stripped before matching.
        let container = Shell.run("/usr/sbin/diskutil", ["apfs", "list"], timeout: 12).stdout
        var capacity: Double?
        var inUse: Double?
        for raw in container.split(separator: "\n") {
            let line = raw.replacingOccurrences(of: "|", with: "")
                .trimmingCharacters(in: .whitespaces)
            if capacity == nil, line.hasPrefix("Size (Capacity Ceiling)") {
                capacity = bytes(in: line)
            } else if inUse == nil, line.hasPrefix("Capacity In Use By Volumes") {
                inUse = bytes(in: line)
            }
        }
        if let capacity { metrics.diskTotalGB = capacity / 1_000_000_000 }
        if let inUse { metrics.diskUsedGB = inUse / 1_000_000_000 }
        return metrics
    }

    private static func bytes(in line: String) -> Double? {
        // e.g. "Size (Capacity Ceiling):   1000240963584 B (1.0 TB)"
        let parts = line.split(separator: " ")
        guard let index = parts.firstIndex(of: "B"), index > 0 else { return nil }
        return Double(parts[index - 1])
    }

    /// The same metrics from another machine, over the SSH trust you already have.
    static func remoteMetrics(sshHost: String) -> HostMetrics {
        var metrics = HostMetrics(collectedAt: Date())
        let script = "echo CPU:$(top -l 1 -s 0 -n 0 | awk '/CPU usage/{print $3+$5}'); "
            + "echo MEMTOTAL:$(sysctl -n hw.memsize); "
            + "echo MEMUSED:$(top -l 1 -s 0 -n 0 | awk '/PhysMem/{print $2}'); "
            + "echo DISK:$(df -k / | tail -1 | awk '{print $2\" \"$3}')"
        let result = Shell.run("/usr/bin/ssh",
                               ["-o", "BatchMode=yes", "-o", "ConnectTimeout=4",
                                "-o", "StrictHostKeyChecking=accept-new", sshHost, script],
                               timeout: 15)
        guard result.succeeded else { return metrics }

        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch parts[0] {
            case "CPU": metrics.cpuPct = Double(value)?.rounded()
            case "MEMTOTAL": metrics.memTotalGB = Double(value).map { $0 / 1_073_741_824 }
            case "MEMUSED":
                let numeric = Double(value.dropLast()) ?? 0
                metrics.memUsedGB = value.hasSuffix("M") ? numeric / 1024 : numeric
            case "DISK":
                let fields = value.split(separator: " ").compactMap { Double($0) }
                if fields.count == 2 {
                    metrics.diskTotalGB = fields[0] / 1_048_576
                    metrics.diskUsedGB = fields[1] / 1_048_576
                }
            default: break
            }
        }
        return metrics
    }
}
