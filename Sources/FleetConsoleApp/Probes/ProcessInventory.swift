import Foundation
import FleetCore

/// The machine's full process table, as rows you can sort, filter and inspect.
///
/// The first sampler collapsed everything into named groups for the treemap —
/// the right shape for a market map, the wrong shape for a console. A console
/// needs the rows themselves: one row per process, with its parent, its user,
/// its listening ports, and enough of the command line to know what it is.
///
/// Everything comes from the same `ps` + `lsof` pair the controller already
/// trusts (`ProcessTable.capture`), so the app and the daemon can never
/// disagree about what a process is. No root: `lsof` scope is this user's
/// listeners, which is the scope FleetConsole claims everywhere else too.

/// What `ps -o state` means, in words, with a tone.
///
/// The raw field is one letter plus BSD modifiers (`S+`, `Ss`, `R<`). Only the
/// first letter carries the scheduler state; the modifiers say things like
/// "session leader" and "foreground process group", which are real but are not
/// health, so they are kept on the row and not folded in here.
///
/// The tones are the interesting part. Three of these seven are *neutral* —
/// sleeping, idle and running are all completely normal, and colouring "running"
/// green would make a machine's process list a wall of green that says nothing.
/// Only the two states you would act on get a hue.
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
        // A stopped process was SIGSTOPped and is not coming back on its own;
        // a zombie is holding a table entry its parent never reaped. Both are
        // things you would do something about. The rest is Tuesday.
        case .stopped, .uninterruptible: return .warn
        case .zombie: return .bad
        case .unknown: return .unknown
        case .running, .sleeping, .idle: return .neutral
        }
    }
}

struct ProcessRow: Identifiable, Equatable {
    /// The pid. Stable for the life of the process; the row's identity is the
    /// process's identity.
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
    /// Listening TCP ports bound by this process (this user's processes only —
    /// `lsof` without root sees no further, and the row says so rather than
    /// drawing an empty port list for a root daemon).
    var ports: [Int]
    /// `ps -o lstart` — the PID-reuse signature. Carried so an inspector can
    /// prove it is looking at the same process the list showed a second ago.
    var startSignature: String
    /// Raw `ps -o state`, modifiers included. Interpreted by `state`.
    var stateField: String

    var state: ProcessState { ProcessState(rawField: stateField) }

    /// What a human would call it: bundle-style display name with the helper
    /// suffixes left intact at row level (helpers are real processes; only the
    /// map used to fold them).
    var displayName: String { name }

    var isKernelTask: Bool { pid == 0 }

    /// Whether this process belongs to the logged-in user.
    ///
    /// The first of the three gates on **End Process**. It is a comparison
    /// against the real effective uid rather than a name match, because a
    /// username can repeat across a uid boundary and the kernel only cares
    /// about the number.
    var isOwnedByCurrentUser: Bool { uid == geteuid() }
}

@Observable
@MainActor
final class ProcessInventory {
    private(set) var rows: [ProcessRow] = []
    private(set) var capturedAt: Date?

    /// pid → children, rebuilt with each capture. The inspector's process tree
    /// reads this rather than re-walking the table.
    private(set) var childrenOf: [Int32: [ProcessRow]] = [:]

    /// Slower than the meter cadence: `ps -Ao` over every process on the
    /// machine costs far more than reading a Mach counter, and process weights
    /// do not meaningfully change in two seconds.
    static let interval: TimeInterval = 4

    private let queue = DispatchQueue(label: "com.fleetconsole.app.processes")
    // Nonisolated so `deinit` can invalidate it; nothing observes this handle.
    @ObservationIgnored nonisolated(unsafe) private var timer: Timer?
    private var sampling = false

    init(interval: TimeInterval = FleetConfig.UIConfig.Intervals().clampedProcessSample) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        sample()
    }

    /// The run loop holds the timer even though the closure is weak, so it has to
    /// be invalidated here or a per-view instance would strand a live `ps` tick.
    deinit {
        timer?.invalidate()
    }

    func sample() {
        guard !sampling else { return }
        sampling = true
        queue.async { [weak self] in
            let collected = Self.collect()
            Task { @MainActor in
                guard let self else { return }
                if self.rows != collected { self.rows = collected }
                self.childrenOf = Dictionary(grouping: collected, by: \.ppid)
                self.capturedAt = Date()
                self.sampling = false
            }
        }
    }

    func row(_ pid: Int32) -> ProcessRow? {
        rows.first { $0.pid == pid }
    }

    /// The heaviest processes, by each of the two weights that actually cost you
    /// something. Two lists rather than one sorted table, because the process
    /// eating your battery and the process eating your RAM are usually different
    /// processes and a single ranking hides whichever one you did not sort by.
    ///
    /// `kernel_task` is dropped from the CPU list on purpose: it is pid 0's
    /// sibling, it is permanently near the top on a warm Mac, and it is the one
    /// row on the list you can do nothing about.
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

    // MARK: - Termination

    /// Why a process cannot be ended, in the words the UI shows.
    ///
    /// Modelled as a reason rather than a `Bool` because a disabled control that
    /// does not say why invites exactly the question it is refusing to answer —
    /// the same argument the Processes module's disabled **Kill Process** item
    /// already makes.
    enum TerminationBlock: Equatable {
        /// The config flag is off. This is the default and it is not a failure.
        case notEnabled
        /// The process belongs to another user, or to the system.
        case notOwned(user: String)
        /// The pid is gone, or is no longer the process the row was drawn from.
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

    /// The gates that can be answered from memory. `nil` means the verb is
    /// offered — not that the signal will be sent.
    ///
    /// **This is called from a view body, so it must not touch the process
    /// table.** It used to end with `if !stillTheSameProcess(row)`, which shells
    /// out to `/bin/ps` and blocks in `waitUntilExit`, and `waitUntilExit` spins
    /// the run loop: the layout pass that called this got re-entered by
    /// CoreAnimation's commit, SwiftUI's AttributeGraph hit
    /// `AG::precondition_failure`, and the app aborted. Every render of the
    /// Processes popover, for every row, the moment the feature was switched on
    /// — which is why turning `allowProcessTermination` on had never once
    /// produced a working End Process button. The flag being off by default is
    /// the only reason this had not been seen.
    ///
    /// The third gate is not lost, it has moved to where it belongs. Whether the
    /// pid is *still* the process this row was drawn from cannot be answered at
    /// render time anyway: the answer would be seconds stale by the time anyone
    /// clicked. It is re-read inside `terminate(_:)`, immediately before the
    /// signal, which is both correct and what the README already claims happens.
    func terminationBlock(for row: ProcessRow, enabled: Bool) -> TerminationBlock? {
        if !row.isOwnedByCurrentUser { return .notOwned(user: row.user) }
        if !enabled { return .notEnabled }
        return nil
    }

    /// Re-reads the pid's start signature and compares it to the one the row was
    /// built with.
    ///
    /// This is the PID-reuse guard the controller has always applied to its own
    /// services (threat model T2), applied here to a process nobody supervises.
    /// The sampler runs every few seconds and a row can sit on screen for
    /// minutes, so "the pid in front of me" and "the pid I am about to signal"
    /// are genuinely different claims — a pid freed and reallocated in between
    /// would otherwise take the signal meant for something else.
    func stillTheSameProcess(_ row: ProcessRow) -> Bool {
        let live = Shell.run("/bin/ps", ["-o", "lstart=", "-p", "\(row.pid)"], timeout: 4)
        guard live.succeeded else { return false }
        let signature = live.stdout.split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return !signature.isEmpty && signature == row.startSignature
    }

    /// SIGTERM, and only SIGTERM.
    ///
    /// There is no escalation to SIGKILL here, deliberately. The controller
    /// escalates for services it launched, because it knows what it started and
    /// owns the consequences of stopping it. This verb does not: it asks a
    /// process you own to exit, and a process that declines is a process you
    /// should look at rather than one the menu bar should overrule.
    ///
    /// Returns the block that stopped it, or `nil` on a signal sent. The guards
    /// are re-run *here* rather than trusted from the caller — the alert the user
    /// confirmed was drawn from a snapshot, and this is the last moment before
    /// the syscall.
    @discardableResult
    func terminate(_ row: ProcessRow, enabled: Bool) -> TerminationBlock? {
        if let block = terminationBlock(for: row, enabled: enabled) { return block }
        // The PID-reuse gate, here and only here. It re-reads `lstart` for the
        // pid and compares it to the signature this row was built with, so a pid
        // freed and reallocated between the sample and the click cannot take a
        // signal meant for something else (threat model T2).
        //
        // It used to run in `terminationBlock` as well, which put a synchronous
        // `/bin/ps` inside a SwiftUI view body and crashed the app. This is the
        // right place for it regardless of that: a check performed at render
        // time is already stale by the time anyone acts on it, and this runs in
        // the same call as the `kill`.
        guard stillTheSameProcess(row) else { return .gone }
        kill(row.pid, SIGTERM)
        sample()
        return nil
    }

    /// Walks ppid links to launchd. Cycle-safe: a reused or missing parent
    /// stops the walk rather than looping.
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

    // MARK: - Collection

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

    /// `getpwuid` once per uid per sample run — never per row.
    nonisolated private static func userName(for uid: uid_t) -> String {
        guard let entry = getpwuid(uid), let name = entry.pointee.pw_name else {
            return "\(uid)"
        }
        return String(cString: name)
    }
}
