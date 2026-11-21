import Foundation
import FleetCore

enum ProcessState: String, Codable, Sendable {
    case running, sleeping, idle, stopped, uninterruptible, zombie, unknown

    init(rawField: String) {
        switch rawField.first {
        case "R": self = .running
        case "S": self = .sleeping
        case "I": self = .idle
        case "T": self = .stopped
        case "U", "D": self = .uninterruptible
        case "Z": self = .zombie
        default: self = .unknown
        }
    }

    var label: String {
        switch self {
        case .running: return "running"
        case .sleeping: return "sleeping"
        case .idle: return "idle"
        case .stopped: return "stopped"
        case .uninterruptible: return "in kernel wait"
        case .zombie: return "zombie"
        case .unknown: return "unknown"
        }
    }

    var tone: StatusTone {
        switch self {
        case .stopped, .uninterruptible: return .warn
        case .zombie: return .bad
        case .unknown: return .unknown
        case .running, .sleeping, .idle: return .neutral
        }
    }
}

struct ProcessRow: Identifiable, Equatable {
    let id: Int32
    var pid: Int32
    var ppid: Int32
    var pgid: Int32
    var uid: uid_t
    var user: String
    var name: String
    var commandLine: String
    var cpuPercent: Double
    var residentBytes: Int64
    var ports: [Int]
    var startSignature: String
    var stateField: String

    var state: ProcessState { ProcessState(rawField: stateField) }

    var displayName: String { name }

    var isKernelTask: Bool { pid == 0 }

    var isOwnedByCurrentUser: Bool { uid == geteuid() }
}

@Observable
@MainActor
final class ProcessInventory {
    private(set) var rows: [ProcessRow] = []
    struct CapturedProcesses: Identifiable {
        let id: Date
        let processes: [InvestigationRequest.ProcessEvidence]
        var time: Date { id }
    }
    private(set) var observations: [CapturedProcesses] = []
    private(set) var capturedAt: Date?

    private(set) var childrenOf: [Int32: [ProcessRow]] = [:]

    static let interval: TimeInterval = 4

    private let queue = DispatchQueue(label: "com.fleetconsole.app.processes")
    @ObservationIgnored nonisolated(unsafe) private var timer: Timer?
    @ObservationIgnored private var sampling = false

    init(interval: TimeInterval = FleetConfig.UIConfig.Intervals().clampedProcessSample) {
        #if FLEET_SURFACE_RENDERER
        if CommandLine.arguments.contains(SurfaceRenderer.flag) {
            rows = Fixtures.processRows
            childrenOf = Dictionary(grouping: rows, by: \.ppid)
            capturedAt = Date()
            return
        }
        #endif
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        sample()
    }

    deinit {
        timer?.invalidate()
    }

    func sample() {
        #if FLEET_SURFACE_RENDERER
        if CommandLine.arguments.contains(SurfaceRenderer.flag) { return }
        #endif
        guard !sampling else { return }
        sampling = true
        queue.async { [weak self] in
            let collected = Self.collect()
            Task { @MainActor in
                guard let self else { return }
                if self.rows != collected { self.rows = collected }
                self.childrenOf = Dictionary(grouping: collected, by: \.ppid)
                let captured = Date()
                self.capturedAt = captured
                let cpu = ProcessWeight.cpu.ranked(collected, limit: 24)
                let memory = ProcessWeight.memory.ranked(collected, limit: 24)
                var seen = Set<Int32>()
                let bounded = (cpu + memory).filter { seen.insert($0.pid).inserted }
                self.observations.append(CapturedProcesses(id: captured, processes: bounded.map(InvestigationRequest.ProcessEvidence.init)))
                if self.observations.count > 120 { self.observations.removeFirst(self.observations.count - 120) }
                self.sampling = false
            }
        }
    }

    func row(_ pid: Int32) -> ProcessRow? {
        rows.first { $0.pid == pid }
    }

    func topByCPU(_ limit: Int = 5) -> [ProcessRow] {
        rows.filter { !$0.isKernelTask && $0.name != "kernel_task" }
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(limit)
            .filter { $0.cpuPercent > 0 }
    }

    func topByMemory(_ limit: Int = 5) -> [ProcessRow] {
        rows.filter { !$0.isKernelTask }
            .sorted { $0.residentBytes > $1.residentBytes }
            .prefix(limit)
            .filter { $0.residentBytes > 0 }
    }

    enum TerminationBlock: Equatable {
        case notEnabled
        case notOwned(user: String)
        case gone

        var explanation: String {
            switch self {
            case .notEnabled:
                return "Ending processes is off. Turn on ui.features.allowProcessTermination "
                    + "in config.json to enable it."
            case .notOwned(let user):
                return "This process belongs to \(user). FleetConsole only ever signals "
                    + "processes you own."
            case .gone:
                return "This pid is no longer the process this row was drawn from."
            }
        }
    }

    func terminationBlock(for row: ProcessRow, enabled: Bool) -> TerminationBlock? {
        if !row.isOwnedByCurrentUser { return .notOwned(user: row.user) }
        if !enabled { return .notEnabled }
        return nil
    }

    func stillTheSameProcess(_ row: ProcessRow) -> Bool {
        let live = Shell.run("/bin/ps", ["-o", "lstart=", "-p", "\(row.pid)"], timeout: 4)
        guard live.succeeded else { return false }
        let signature = live.stdout.split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return !signature.isEmpty && signature == row.startSignature
    }

    @discardableResult
    func terminate(_ row: ProcessRow, enabled: Bool) -> TerminationBlock? {
        if let block = terminationBlock(for: row, enabled: enabled) { return block }
        guard stillTheSameProcess(row) else { return .gone }
        kill(row.pid, SIGTERM)
        sample()
        return nil
    }

    func ancestry(of row: ProcessRow, limit: Int = 6) -> [ProcessRow] {
        var chain: [ProcessRow] = []
        var current = row.ppid
        var seen: Set<Int32> = [row.pid]
        while current > 1, chain.count < limit, !seen.contains(current),
              let parent = self.row(current) {
            chain.append(parent)
            seen.insert(current)
            current = parent.ppid
        }
        return chain
    }

    nonisolated private static func collect() -> [ProcessRow] {
        let table = ProcessTable.capture(includeListeners: true)
        var portsByPID: [Int32: [Int]] = [:]
        for listener in table.listeners {
            portsByPID[listener.pid, default: []].append(listener.port)
        }

        var names: [uid_t: String] = [:]
        var rows: [ProcessRow] = []
        rows.reserveCapacity(table.byPID.count)
        for process in table.byPID.values {
            let user = names[process.uid] ?? Self.userName(for: process.uid)
            names[process.uid] = user
            rows.append(ProcessRow(
                id: process.pid,
                pid: process.pid,
                ppid: process.ppid,
                pgid: process.pgid,
                uid: process.uid,
                user: user,
                name: process.executableName,
                commandLine: process.commandLine,
                cpuPercent: process.cpuPct,
                residentBytes: Int64(process.rssKB * 1024),
                ports: (portsByPID[process.pid] ?? []).sorted(),
                startSignature: process.startSignature,
                stateField: process.state))
        }
        return rows.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    nonisolated private static func userName(for uid: uid_t) -> String {
        guard let entry = getpwuid(uid), let name = entry.pointee.pw_name else {
            return "\(uid)"
        }
        return String(cString: name)
    }
}
