import Foundation
import Darwin
import FleetCore

/// The controller. Owns every managed process, the registry, the reconciliation
/// sweep and the local RPC surface.
///
/// Concurrency model: one serial queue owns all mutable state and the SQLite
/// handle. Anything that can block for a meaningful time (subprocess capture,
/// health checks, socket writes to subscribers) happens off that queue and posts
/// its result back onto it.
final class Controller {
    static let version = "1.0.0"

    private let queue = DispatchQueue(label: "com.fleetconsole.controller")
    private let workQueue = DispatchQueue(label: "com.fleetconsole.work", attributes: .concurrent)
    private let broadcastQueue = DispatchQueue(label: "com.fleetconsole.broadcast")

    private let registry: Registry
    private var config: FleetConfig
    private var configWarning: String?

    private var services: [String: ServiceRecord] = [:]
    private var unmanagedList: [UnmanagedProcess] = []
    private var externalList: [ExternalService] = []
    private var sessionList: [AgentSession] = []
    private var deviceList: [DeviceRecord] = []
    private var tailscale: TailscaleStatus?

    private var subscribers: [ObjectIdentifier: SocketConnection] = [:]
    private var daemon: DaemonInfo

    /// Broadcast coalescing state, owned by `queue`: one write in flight, one pending.
    private var broadcastInFlight = false
    private var broadcastPending = false

    /// Services we asked to stop, with the deadline after which SIGTERM becomes SIGKILL.
    private var pendingStops: [String: Date] = [:]
    /// Services with an in-flight health check, so ticks cannot pile them up.
    private var healthInFlight: Set<String> = []
    private var lastHealthCheckAt: [String: Date] = [:]
    private var lastReconcileAt: Date?
    private var lastDeviceProbeAt: Date?
    private var expiringNotified: Set<String> = []

    private var tickTimer: DispatchSourceTimer?
    private var sigchldSource: DispatchSourceSignal?
    private var server: UnixSocketServer?

    init() throws {
        self.registry = try Registry()
        let hostName = ProcessInfo.processInfo.hostName
        let ts = TailscaleClient.status().status
        let (cfg, warning) = FleetConfig.loadOrCreate(selfHostName: hostName,
                                                      selfTailscaleName: ts?.selfNode?.shortName)
        self.config = cfg
        self.configWarning = warning
        self.tailscale = ts
        self.daemon = DaemonInfo(version: Self.version,
                                 pid: getpid(),
                                 startedAt: Date(),
                                 tickIntervalSec: cfg.supervisorTickSec,
                                 socketPath: FleetPaths.socket.path)
    }

    // MARK: - Lifecycle

    func start() throws {
        try queue.sync {
            try recoverFromRestart()
            try recordPreviousGenerationCrash()
            try registry.append(.daemonStarted, service: nil,
                                detail: "fleetd \(Self.version) pid \(getpid()), tick \(Int(config.supervisorTickSec))s")
            if let configWarning {
                FleetLog.warn(configWarning)
            }
        }

        installSIGCHLDHandler()

        let server = UnixSocketServer(path: FleetPaths.socket.path)
        server.onRejectedPeer = { [weak self] uid in
            self?.queue.async {
                _ = try? self?.registry.append(.rejectedPeer, service: nil,
                                           detail: "connection from uid \(uid) refused (daemon uid \(geteuid()))")
            }
            FleetLog.warn("rejected connection from uid \(uid)")
        }
        try server.start()
        self.server = server
        FleetLog.info("listening on \(FleetPaths.socket.path)")

        startTicking()

        // Blocking accept loop; each connection is handled on its own thread.
        server.run { [weak self] conn in
            self?.handleConnection(conn)
        }
    }

    func shutdown() {
        // Ticks and the accept loop stop first: they would otherwise keep writing to a
        // registry we are about to close.
        tickTimer?.cancel()
        server?.stop()
        queue.sync {
            _ = try? registry.append(.daemonStopping, service: nil,
                                 detail: "controller stopping; \(services.values.filter { !$0.state.isTerminal }.count) managed services left running")
            // The process leaves through exit() immediately after this, so `deinit` will
            // not run: this is the only point where the WAL gets checkpointed and the
            // database file is released cleanly.
            registry.close()
        }
        // The stop event is on the timeline, so the marker has nothing left to
        // explain. Clearing it here keeps the clean path from leaving a file
        // that would otherwise be consumed by the next startup for no reason.
        StopMarker.clear()
        FleetLog.info("controller stopped")
    }

    /// A controller that dies through fatalError, SIGKILL or a panic writes nothing at
    /// all, so an abnormal exit is only visible as the *absence* of a `daemonStopping`
    /// after the previous `daemonStarted`. Recorded here, before this generation's own
    /// start event, so the crash lands on the timeline where it actually happened.
    ///
    /// The absence of a stop event is not on its own evidence of a crash, which is what
    /// this used to treat it as. A generation that was signalled and then killed before
    /// it could finish shutting down also leaves no stop event, and that is a deliberate
    /// restart — the overwhelmingly common case here, since `Scripts/build-app.sh`
    /// bootouts the agent on every build. `StopMarker` is written by the signal handler
    /// before any lock is taken, so it survives the kill and separates the two.
    private func recordPreviousGenerationCrash() throws {
        // Consumed unconditionally: one signal explains at most one exit, and a
        // marker left behind by a clean stop must not excuse a later crash.
        let signalled = StopMarker.consume()

        let lifecycle = (try? registry.events(kinds: [.daemonStarted, .daemonStopping, .daemonCrashed],
                                              limit: 1)) ?? []
        guard let last = lifecycle.first, last.kind == .daemonStarted else { return }

        if let signalled {
            try registry.append(.daemonStopping, service: nil,
                                detail: "previous controller was told to stop (\(signalled)) and exited "
                                    + "before it finished shutting down "
                                    + "(started \(Fmt.relative(last.ts)))")
            FleetLog.info("previous controller generation was signalled to stop "
                            + "(started \(Fmt.relative(last.ts)))")
            return
        }

        try registry.append(.daemonCrashed, service: nil,
                            detail: "previous controller exited without a stop event and without a stop "
                                + "signal (started \(Fmt.relative(last.ts)): \(last.detail))")
        FleetLog.warn("previous controller generation exited abnormally (started \(Fmt.relative(last.ts)))")
    }

    /// Crash-consistent startup: every non-terminal record is re-verified against
    /// live processes before we serve a single snapshot (threat model T3).
    private func recoverFromRestart() throws {
        let table = ProcessTable.capture()
        for var record in try registry.services() {
            if record.state.isTerminal {
                services[record.id] = record
                continue
            }
            let alive = isAlive(record, in: table)
            if alive {
                record.evidence.processExists = true
                record.evidence.checkedAt = Date()
                services[record.id] = record
                try registry.upsert(record)
                FleetLog.info("readopted \(record.friendlyName) pid \(record.pid ?? -1)")
            } else {
                record.state = .crashed
                record.evidence = Evidence(processExists: false, checkedAt: Date())
                record.updatedAt = Date()
                services[record.id] = record
                try registry.upsert(record)
                try registry.append(.reconcileMissing, service: record,
                                    detail: "process was gone when the controller restarted; record closed")
            }
        }
        try registry.pruneTerminated(olderThan: 7 * 24 * 3600)
        unmanagedList = (try? registry.unmanaged()) ?? []
        deviceList = (try? registry.devices()) ?? []
    }

    private func startTicking() {
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + 0.5, repeating: config.supervisorTickSec)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        tickTimer = timer
    }

    /// SIGCHLD gives us real exit codes. Without it, children would linger as zombies
    /// and "crashed vs stopped" would be a guess.
    private func installSIGCHLDHandler() {
        signal(SIGCHLD, SIG_DFL)
        let source = DispatchSource.makeSignalSource(signal: SIGCHLD, queue: workQueue)
        source.setEventHandler { [weak self] in self?.reapChildren() }
        source.resume()
        sigchldSource = source
    }

    private func reapChildren() {
        while true {
            var status: Int32 = 0
            let pid = waitpid(-1, &status, WNOHANG)
            if pid <= 0 { break }
            let exitCode: Int32
            if (status & 0x7f) == 0 {
                exitCode = (status >> 8) & 0xff
            } else {
                exitCode = -(status & 0x7f)   // negative = terminated by that signal
            }
            queue.async { [weak self] in
                self?.noteChildExit(pid: pid, exitCode: exitCode)
            }
        }
    }

    private func noteChildExit(pid: Int32, exitCode: Int32) {
        guard var record = services.values.first(where: { $0.pid == pid && !$0.state.isTerminal }) else { return }
        let requested = pendingStops[record.id] != nil || record.state == .stopping
        record.lastExitCode = exitCode
        record.state = requested ? .stopped : .crashed
        record.evidence.processExists = false
        record.evidence.checkedAt = Date()
        record.updatedAt = Date()
        services[record.id] = record
        pendingStops.removeValue(forKey: record.id)
        try? registry.upsert(record)
        _ = try? registry.append(requested ? .stopped : .crashed, service: record,
                             detail: requested
                                ? "exited with code \(exitCode) after stop request"
                                : "exited unexpectedly with code \(exitCode)")
        FleetLog.info("\(record.friendlyName) (\(record.shortID)) → \(record.state.rawValue), exit \(exitCode)")
        broadcastSnapshot()
    }

    // MARK: - Supervisor tick

    private func tick() {
        // Subprocess capture happens off the state queue.
        let table = ProcessTable.capture()
        let dueForReconcile = queue.sync { () -> Bool in
            guard let last = lastReconcileAt else { return true }
            return Date().timeIntervalSince(last) >= config.reconcileIntervalSec
        }
        let dueForDevices = queue.sync { () -> Bool in
            guard let last = lastDeviceProbeAt else { return true }
            return Date().timeIntervalSince(last) >= config.deviceProbeIntervalSec
        }

        queue.sync {
            self.daemon.lastTickAt = Date()
            // A `ps` that did not run tells us nothing about liveness. Judging services
            // against an empty table would declare every one of them crashed, so the
            // tick reports itself and stops — evidence simply goes stale, which the
            // attention rules already surface honestly.
            guard !table.processProbeFailed else {
                FleetLog.warn("skipping evaluation: ps probe failed; no liveness verdict this tick")
                return
            }
            self.evaluateAll(table: table)
            if dueForReconcile {
                self.runReconcile(table: table)
            }
        }
        scheduleDueHealthChecks()
        if dueForDevices { probeDevices() }
        broadcastSnapshot()
    }

    private func evaluateAll(table: ProcessTable) {
        let now = Date()
        for var record in services.values where !record.state.isTerminal {
            // Evidence captured before a service started says nothing about it.
            // Capturing the process table takes a few hundred milliseconds and
            // happens *before* this queue is entered, so a service launched inside
            // that window used to be judged against a snapshot that predates it,
            // declared "crashed" in the same second, and then survive as an orphan
            // holding its port — precisely the leak this controller exists to stop.
            guard table.capturedAt.timeIntervalSince(record.startedAt) > 0.25 else { continue }

            let alive = isAlive(record, in: table)
            record.evidence.checkedAt = now
            record.evidence.processExists = alive

            if !alive {
                // SIGCHLD usually gets here first; this is the backstop for a process
                // that was never our direct child or whose signal we missed.
                let requested = pendingStops[record.id] != nil || record.state == .stopping
                record.state = requested ? .stopped : .crashed
                record.evidence.listeningPorts = []
                record.updatedAt = now
                services[record.id] = record
                pendingStops.removeValue(forKey: record.id)
                try? registry.upsert(record)
                _ = try? registry.append(requested ? .stopped : .crashed, service: record,
                                     detail: requested ? "process group gone after stop request"
                                                       : "process group vanished without a stop request")
                checkForEscapedPorts(record, table: table)
                continue
            }

            // A stop is in flight: refresh the evidence but never re-derive the
            // state, or a healthy-but-dying service would flip back to "healthy"
            // between SIGTERM and exit.
            if record.state == .stopping {
                if let pgid = record.pgid {
                    record.evidence.listeningPorts = table.listeningPorts(inGroup: pgid)
                    record.resources = table.resourceUsage(inGroup: pgid)
                }
                record.updatedAt = now
                services[record.id] = record
                try? registry.upsert(record)
                continue
            }

            guard let pgid = record.pgid else { continue }
            record.evidence.listeningPorts = table.listeningPorts(inGroup: pgid)
            record.evidence.portScanRan = true
            record.resources = table.resourceUsage(inGroup: pgid)

            // Rolling history for the sparklines. Capped so a service that runs for
            // a week cannot grow its own record without bound.
            record.cpuHistory.append(record.resources.cpuPct ?? 0)
            record.memHistory.append(record.resources.memMB ?? 0)
            if record.cpuHistory.count > ServiceRecord.historyLimit {
                record.cpuHistory.removeFirst(record.cpuHistory.count - ServiceRecord.historyLimit)
            }
            if record.memHistory.count > ServiceRecord.historyLimit {
                record.memHistory.removeFirst(record.memHistory.count - ServiceRecord.historyLimit)
            }

            // A paused process is deliberately doing nothing: it keeps its ports and
            // its memory, so liveness and resources still update, but no health check
            // is run against it and no lease decision is re-derived from silence.
            if record.state == .paused {
                record.updatedAt = now
                services[record.id] = record
                try? registry.upsert(record)
                continue
            }

            var breaches: [String] = []
            if let limit = record.budget.cpuWarnPct, let cpu = record.resources.cpuPct, cpu > limit {
                breaches.append(String(format: "CPU %.0f%% over %.0f%% budget", cpu, limit))
            }
            if let limit = record.budget.memWarnMB, let mem = record.resources.memMB, mem > limit {
                breaches.append(String(format: "memory %.0f MB over %.0f MB budget", mem, limit))
            }
            if !record.budget.allowedPorts.isEmpty {
                let stray = record.evidence.listeningPorts.filter { !record.budget.allowedPorts.contains($0) }
                if !stray.isEmpty {
                    breaches.append("listening on \(stray.map { ":\($0)" }.joined(separator: " ")) outside allowed ports")
                }
            }
            let newBreaches = Set(breaches).subtracting(record.budgetBreaches)
            if !newBreaches.isEmpty {
                let isPort = breaches.contains { $0.contains("outside allowed ports") }
                _ = try? registry.append(isPort ? .portViolation : .budgetWarning, service: record,
                                     detail: newBreaches.sorted().joined(separator: "; "))
            }
            record.budgetBreaches = breaches

            // Lease and hard runtime ceiling — the two independent leak defences (T1).
            //
            // Already-expired records are not re-evaluated. For a launched service
            // that guard is invisible, because the stop below takes it out of this
            // loop within a tick. For a *claimed* one it is what stops the loop:
            // the record stays expired and the process stays alive by design, so
            // without it every tick would append another `leaseExpired` event for
            // as long as the process ran.
            let uptime = now.timeIntervalSince(record.startedAt)
            var reap: String?
            if record.state != .expired {
                if let maxRuntime = record.budget.maxRuntimeSec, uptime > maxRuntime {
                    reap = "max runtime \(Fmt.duration(maxRuntime)) exceeded (running \(Fmt.duration(uptime)))"
                    _ = try? registry.append(.maxRuntimeExceeded, service: record, detail: reap!)
                } else if now >= record.leaseExpiresAt {
                    reap = "lease expired \(Fmt.relative(record.leaseExpiresAt, now: now)); owner \(record.ownerAgent) did not renew"
                    if !record.isSignallableByController {
                        reap! += ". Claimed, not launched — the controller is reporting this, not acting on it"
                    }
                    _ = try? registry.append(.leaseExpired, service: record, detail: reap!)
                }
            }

            if let reap {
                record.state = .expired
                record.reapedForExpiry = true   // this agent left something running
                record.updatedAt = now
                services[record.id] = record
                try? registry.upsert(record)
                // A claimed record expires on the screen and nowhere else. The
                // state, the event and the attention row all still fire — what
                // does not fire is the signal, because the controller did not
                // start this process and does not own the consequences of ending
                // it. Stopping it is yours to do, where you started it.
                guard record.isSignallableByController else {
                    FleetLog.info("claimed record \(record.friendlyName) (\(record.shortID)) expired: \(reap)")
                    continue
                }
                FleetLog.info("reaping \(record.friendlyName) (\(record.shortID)): \(reap)")
                beginStop(record, reason: reap, requestedBy: "controller")
                continue
            }

            // An expired record keeps that state. Nothing below can improve it, and
            // re-deriving would walk a claimed one back to `expiring` — which
            // re-arms the block above and reinstates the per-tick event storm the
            // guard there exists to prevent.
            guard record.state != .expired else {
                record.updatedAt = now
                services[record.id] = record
                try? registry.upsert(record)
                continue
            }

            let remaining = record.leaseExpiresAt.timeIntervalSince(now)
            let warnWindow = max(30, record.leaseTTLSec * 0.1)
            if remaining <= warnWindow {
                if expiringNotified.insert(record.id).inserted {
                    _ = try? registry.append(.leaseExpiring, service: record,
                                         detail: "lease expires in \(Fmt.duration(remaining)) — renew or it will be stopped")
                }
                record.state = .expiring
            } else {
                expiringNotified.remove(record.id)
                record.state = derivedState(for: record)
            }

            record.updatedAt = now
            services[record.id] = record
            try? registry.upsert(record)
        }
    }

    /// The honesty rule, encoded: "healthy" requires a check that ran and passed.
    /// Without a configured check the best available state is `running` — the UI
    /// renders that as "Running (unverified)".
    private func derivedState(for record: ServiceRecord) -> ServiceState {
        if record.health.kind == .none {
            return record.budgetBreaches.isEmpty ? .running : .degraded
        }
        guard record.evidence.healthCheckRan, let passed = record.evidence.healthPassed else {
            return .starting
        }
        if !passed {
            return record.consecutiveHealthFailures >= record.health.failureThreshold ? .unhealthy : .degraded
        }
        return record.budgetBreaches.isEmpty ? .healthy : .degraded
    }

    private func isAlive(_ record: ServiceRecord, in table: ProcessTable) -> Bool {
        guard let pid = record.pid else { return false }
        if let proc = table.process(pid) {
            // PID-reuse guard: same pid, different start time means a *different* process.
            if let signature = record.startSignature, proc.startSignature != signature {
                return false
            }
            return true
        }
        if let pgid = record.pgid, !table.processes(inGroup: pgid).isEmpty {
            return true
        }
        return false
    }

    /// A service whose group died but whose port is still held did not clean up
    /// properly; that is a leak and it must not disappear silently (T1 residual risk).
    private func checkForEscapedPorts(_ record: ServiceRecord, table: ProcessTable) {
        let survivors = table.listeners.filter { record.declaredPorts.contains($0.port) }
        guard !survivors.isEmpty else { return }
        let detail = survivors
            .map { ":\($0.port) still held by \($0.command) pid \($0.pid)" }
            .joined(separator: "; ")
        _ = try? registry.append(.reapIncomplete, service: record, detail: detail)
        FleetLog.warn("reap incomplete for \(record.friendlyName): \(detail)")
    }

    // MARK: - Health checks

    private func scheduleDueHealthChecks() {
        let due: [ServiceRecord] = queue.sync {
            services.values.filter { record in
                guard record.health.kind != .none, !record.state.isTerminal else { return false }
                guard record.evidence.processExists == true else { return false }
                guard !healthInFlight.contains(record.id) else { return false }
                guard let last = lastHealthCheckAt[record.id] else { return true }
                return Date().timeIntervalSince(last) >= record.health.intervalSec
            }
        }
        guard !due.isEmpty else { return }
        queue.sync {
            for record in due { healthInFlight.insert(record.id) }
        }
        for record in due {
            workQueue.async { [weak self] in
                guard let self else { return }
                let outcome = HealthChecker.check(record.health)
                self.queue.async {
                    self.healthInFlight.remove(record.id)
                    self.lastHealthCheckAt[record.id] = Date()
                    self.applyHealth(outcome, to: record.id)
                }
            }
        }
    }

    private func applyHealth(_ outcome: HealthChecker.Outcome?, to id: String) {
        guard let outcome, var record = services[id], !record.state.isTerminal else { return }
        let previous = record.evidence.healthPassed
        record.evidence.healthCheckRan = true
        record.evidence.healthPassed = outcome.passed
        record.evidence.healthDetail = outcome.detail
        record.evidence.healthLatencyMs = outcome.latencyMs
        record.evidence.checkedAt = Date()
        record.consecutiveHealthFailures = outcome.passed ? 0 : record.consecutiveHealthFailures + 1
        if !outcome.passed { record.healthFailureCount += 1 }

        if record.state != .expiring && record.state != .expired && record.state != .stopping {
            record.state = derivedState(for: record)
        }
        record.updatedAt = Date()
        services[id] = record
        try? registry.upsert(record)

        // Only transitions are recorded, plus the moment a failure crosses its
        // threshold — an event log full of identical lines is not a timeline.
        if previous != outcome.passed {
            _ = try? registry.append(outcome.passed ? .healthPassed : .healthFailed, service: record,
                                 detail: outcome.detail + String(format: " (%.0f ms)", outcome.latencyMs))
        } else if !outcome.passed && record.consecutiveHealthFailures == record.health.failureThreshold {
            _ = try? registry.append(.healthFailed, service: record,
                                 detail: "failed \(record.consecutiveHealthFailures)× in a row: \(outcome.detail)")
        }
        broadcastSnapshot()
    }

    // MARK: - Reconciliation

    private func runReconcile(table: ProcessTable) {
        // A failed `ps`/`lsof` is not an empty machine. Sweeping on one would delete
        // every unmanaged row (losing `firstSeen`) and then re-emit the whole set as new
        // `becameUnmanaged` events on the next good sweep — 447 of 867 events in the live
        // registry were duplicates produced exactly this way. Keep the prior state and
        // do not mark the sweep as done, so the next tick retries.
        guard !table.probeFailed else {
            FleetLog.warn("skipping reconcile: process probe failed"
                          + (table.processProbeFailed ? " (ps)" : "")
                          + (table.listenerProbeFailed ? " (lsof)" : "")
                          + "; keeping the previous unmanaged set")
            return
        }
        let inputs = Reconciler.Inputs(table: table, config: config, services: Array(services.values))
        // Declared local tools are resolved first; whatever they own is then
        // excluded from the unmanaged sweep.
        let tools = Reconciler.externalServices(inputs)
        externalList = tools.services
        let found = Reconciler.scan(inputs, claimedPIDs: tools.claimedPIDs)
        // The coding agents you are actually running, detected rather than registered.
        sessionList = SessionScanner.scan(table: table)
        let known = Set(unmanagedList.map(\.id))
        // A failed write must not become a reset either: `found` carries a fresh
        // `firstSeen` for everything, so falling back to it would age-reset the list.
        guard let merged = try? registry.syncUnmanaged(found) else {
            FleetLog.warn("skipping reconcile: could not persist the unmanaged set; keeping the previous one")
            return
        }
        for process in merged where !known.contains(process.id) {
            let ports = process.ports.isEmpty ? "no listener" : Fmt.ports(process.ports)
            _ = try? registry.append(.becameUnmanaged, service: nil,
                                 detail: "\(process.command) pid \(process.pid) (\(ports)) — \(process.reason.label): \(process.commandLine.prefix(160))")
            FleetLog.warn("unmanaged: \(process.command) pid \(process.pid) \(ports)")
        }
        unmanagedList = merged
        lastReconcileAt = Date()
        daemon.lastReconcileAt = lastReconcileAt
    }

    private func probeDevices() {
        workQueue.async { [weak self] in
            guard let self else { return }
            let status = TailscaleClient.status().status
            let (cfg, previous) = self.queue.sync { (self.config, Dictionary(uniqueKeysWithValues: self.deviceList.map { ($0.id, $0) })) }
            let probed = DeviceProber.probeAll(config: cfg, tailscale: status, previous: previous)
            self.queue.sync {
                self.tailscale = status
                self.deviceList = probed
                self.lastDeviceProbeAt = Date()
                for device in probed { try? self.registry.upsert(device) }
            }
            self.broadcastSnapshot()
        }
    }

    // MARK: - Mutating operations

    private func launch(_ request: LaunchRequest) throws -> ServiceRecord {
        var request = request
        request.leaseTTLSec = min(max(request.leaseTTLSec, 60), config.maxLeaseSec)

        let validated: (argv: [String], cwd: String)
        do {
            validated = try ProcessLauncher.validate(request, config: config)
        } catch {
            _ = try? registry.append(.rejectedLaunch, service: nil,
                                 detail: "\(request.ownerAgent)/\(request.friendlyName): \(error.localizedDescription)")
            throw error
        }

        let id = UUID().uuidString
        let spawned = try ProcessLauncher.spawn(id: id, argv: validated.argv, cwd: validated.cwd,
                                                extraEnv: request.env)

        var record = ServiceRecord(id: id,
                                   friendlyName: request.friendlyName,
                                   ownerAgent: request.ownerAgent,
                                   purpose: request.purpose,
                                   command: validated.argv,
                                   cwd: validated.cwd,
                                   envKeys: request.env.keys.sorted(),   // keys only, never values (T6)
                                   pid: spawned.pid,
                                   pgid: spawned.pgid,
                                   startSignature: spawned.startSignature,
                                   declaredPorts: request.declaredPorts,
                                   startedAt: Date(),
                                   leaseExpiresAt: Date().addingTimeInterval(request.leaseTTLSec),
                                   leaseTTLSec: request.leaseTTLSec,
                                   budget: request.budget,
                                   health: request.health,
                                   state: .starting,
                                   evidence: Evidence(processExists: true, checkedAt: Date()),
                                   stdoutPath: spawned.stdoutPath,
                                   stderrPath: spawned.stderrPath)
        if record.budget.allowedPorts.isEmpty && !record.declaredPorts.isEmpty {
            record.budget.allowedPorts = record.declaredPorts
        }

        services[id] = record
        try registry.upsert(record)
        try registry.append(.registered, service: record,
                            detail: "owner \(record.ownerAgent) — purpose: \(record.purpose)")
        try registry.append(.started, service: record,
                            detail: "pid \(spawned.pid) pgid \(spawned.pgid) in \(record.cwd); lease \(Fmt.duration(request.leaseTTLSec)); argv: \(record.commandLine.prefix(200))")
        FleetLog.info("launched \(record.friendlyName) (\(record.shortID)) pid \(spawned.pid) for \(record.ownerAgent)")
        return record
    }

    /// Adopt an already-running process into the registry.
    ///
    /// The counterpart to `launch`, and deliberately not a weaker version of it.
    /// A launched service is one the controller started, so it owns the
    /// consequences of stopping it. A claimed one was already there when we
    /// arrived: it gets an owner, a purpose, a lease and a timeline, and the
    /// controller still refuses to signal it — see `isSignallableByController`,
    /// which every signal path in this file consults. Claiming buys
    /// **visibility**, not authority, which is why it is safe to offer for a
    /// process whose lifecycle somebody else owns.
    ///
    /// The target is re-verified here rather than trusted from the sweep that
    /// found it: an `UnmanagedProcess.id` is `pid:hash(startSignature)`, so a pid
    /// recycled between the sweep and the click is caught by the same comparison
    /// that guards every signal (threat model T2).
    private func claim(unmanagedID: String, friendlyName: String?, owner: String?,
                       purpose: String?, ttl: Double?, table: ProcessTable) throws -> ServiceRecord {
        guard !table.processProbeFailed else {
            throw FleetError.rejected("the process probe failed; nothing can be verified this moment")
        }

        // Either an id from the unmanaged list, or a bare pid for the case where
        // you are looking at Activity Monitor rather than at this app.
        let known = unmanagedList.first { $0.id == unmanagedID || String($0.pid) == unmanagedID }
        guard let pid = known?.pid ?? Int32(unmanagedID) else {
            throw FleetError.notFound("no unmanaged process matching '\(unmanagedID)'")
        }
        guard let proc = table.process(pid) else {
            throw FleetError.rejected("pid \(pid) is no longer running")
        }
        guard proc.uid == geteuid() else {
            throw FleetError.rejected("pid \(pid) belongs to another user")
        }
        guard proc.pgid != getpgrp() else {
            throw FleetError.rejected("refusing to claim the controller's own process group")
        }
        // The id carries the signature the process was seen with. A mismatch means
        // the number was recycled and this is a different process wearing it.
        if let recorded = known?.id.split(separator: ":").last.map(String.init),
           recorded != Reconciler.stableHash(proc.startSignature) {
            throw FleetError.rejected("pid \(pid) is not the process that was seen at "
                                      + "\(unmanagedID); it has been recycled since the sweep")
        }
        if let existing = services.values.first(where: { $0.pid == pid && !$0.state.isTerminal }) {
            throw FleetError.rejected("pid \(pid) is already registered as "
                                      + "\(existing.friendlyName) (\(existing.shortID))")
        }

        let leaseTTL = min(max(ttl ?? config.defaultLeaseSec, 60), config.maxLeaseSec)
        let name = friendlyName?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? known?.command.nilIfEmpty
            ?? proc.executableName
        let ports = known?.ports ?? table.listeningPorts(inGroup: proc.pgid)

        var record = ServiceRecord(friendlyName: name,
                                   ownerAgent: owner?.nilIfEmpty ?? "operator",
                                   purpose: purpose?.nilIfEmpty ?? "claimed from the unmanaged list",
                                   command: proc.commandLine
                                       .split(separator: " ", omittingEmptySubsequences: true)
                                       .map(String.init),
                                   cwd: "",
                                   pid: proc.pid,
                                   pgid: proc.pgid,
                                   startSignature: proc.startSignature,
                                   declaredPorts: ports,
                                   // Its uptime is its own, not the moment we noticed
                                   // it — a claimed record that resets the clock would
                                   // hide exactly how long a leak has been running.
                                   startedAt: Reconciler.parseStartTime(proc.startSignature)
                                       ?? known?.firstSeen ?? Date(),
                                   leaseExpiresAt: Date().addingTimeInterval(leaseTTL),
                                   leaseTTLSec: leaseTTL,
                                   // No health check: nobody declared one, and the
                                   // best state this can reach is Running (unverified).
                                   state: .running,
                                   evidence: Evidence(processExists: true,
                                                      listeningPorts: ports,
                                                      portScanRan: true,
                                                      checkedAt: Date()),
                                   resources: table.resourceUsage(inGroup: proc.pgid))
        record.claimed = true
        record.claimedAt = Date()

        services[record.id] = record
        try registry.upsert(record)
        try registry.append(.claimed, service: record,
                            detail: "adopted pid \(proc.pid) pgid \(proc.pgid) started \(proc.startSignature)"
                                + (ports.isEmpty ? "" : "; listening on \(ports.map { ":\($0)" }.joined(separator: " "))")
                                + "; owner \(record.ownerAgent) — purpose: \(record.purpose)"
                                + "; lease \(Fmt.duration(leaseTTL)). The controller supervises it "
                                + "and will not signal it.")
        FleetLog.info("claimed \(record.friendlyName) (\(record.shortID)) pid \(proc.pid) for \(record.ownerAgent)")

        // The sweep's own list is stale the moment this returns — the row the user
        // clicked is now a service. Drop it here rather than leaving the process
        // listed as both until the next reconcile.
        unmanagedList.removeAll { $0.pid == pid }
        return record
    }

    /// The one rule claiming does not buy its way out of, in one place.
    ///
    /// Every controller-initiated signal goes through here or through
    /// `verifiedTarget`, so a claimed record cannot be stopped, restarted, paused,
    /// resumed, killed or reaped by us — only reported on.
    private func requireSignallable(_ record: ServiceRecord) throws {
        if let refusal = record.signalRefusal {
            throw FleetError.rejected(refusal)
        }
    }

    private func renew(_ id: String, ttl: Double?) throws -> ServiceRecord {
        guard var record = try registry.resolve(idOrPrefix: id), let live = services[record.id] else {
            throw FleetError.notFound("no service matching '\(id)'")
        }
        record = live
        guard !record.state.isTerminal else {
            throw FleetError.rejected("\(record.friendlyName) is \(record.state.rawValue); relaunch it instead")
        }
        let requested = ttl ?? record.leaseTTLSec
        let clamped = min(max(requested, 60), config.maxLeaseSec)
        record.leaseTTLSec = clamped
        record.leaseExpiresAt = Date().addingTimeInterval(clamped)
        record.lastRenewedAt = Date()
        if record.state == .expiring { record.state = derivedState(for: record) }
        expiringNotified.remove(record.id)
        record.updatedAt = Date()
        services[record.id] = record
        try registry.upsert(record)
        try registry.append(.leaseRenewed, service: record,
                            detail: "lease extended by \(Fmt.duration(clamped)) → expires \(Fmt.relative(record.leaseExpiresAt))")
        return record
    }

    /// Verify-then-signal. Nothing is ever signalled without re-proving the target
    /// is still the process we started (threat model T2).
    private func beginStop(_ record: ServiceRecord, reason: String, requestedBy: String) {
        var record = record
        // Defence in depth. The two callers that can be reached from outside —
        // the stop RPC and `restart` — refuse a claimed record with a message
        // first, because a verb that silently does nothing is worse than one that
        // says no. This is the invariant underneath them, so a third caller added
        // later cannot signal a process the controller did not start.
        guard record.isSignallableByController else {
            _ = try? registry.append(.rejectedLaunch, service: record,
                                 detail: "\(requestedBy) asked to stop a claimed record: \(reason). "
                                     + (record.signalRefusal ?? ""))
            FleetLog.warn("refusing to stop claimed record \(record.friendlyName) (\(record.shortID))")
            return
        }
        guard let pid = record.pid, let pgid = record.pgid, pgid > 1 else {
            record.state = .stopped
            record.updatedAt = Date()
            services[record.id] = record
            try? registry.upsert(record)
            return
        }
        guard pgid != getpgrp() else {
            _ = try? registry.append(.pidReuseSuspected, service: record,
                                 detail: "refusing to signal process group \(pgid): it is the controller's own group")
            return
        }

        let table = ProcessTable.capture(includeListeners: false)
        if let proc = table.process(pid), let signature = record.startSignature,
           proc.startSignature != signature {
            _ = try? registry.append(.pidReuseSuspected, service: record,
                                 detail: "pid \(pid) is now '\(proc.commandLine.prefix(80))' started \(proc.startSignature); expected start \(signature). No signal sent.")
            record.state = .crashed
            record.evidence.processExists = false
            record.updatedAt = Date()
            services[record.id] = record
            try? registry.upsert(record)
            FleetLog.warn("pid reuse suspected for \(record.friendlyName); refusing to signal")
            return
        }
        guard !table.processes(inGroup: pgid).isEmpty || table.process(pid) != nil else {
            record.state = .stopped
            record.evidence.processExists = false
            record.updatedAt = Date()
            services[record.id] = record
            try? registry.upsert(record)
            _ = try? registry.append(.stopped, service: record, detail: "already gone when stop was requested")
            return
        }

        _ = try? registry.append(.stopRequested, service: record, detail: "\(requestedBy): \(reason)")
        record.state = .stopping
        record.updatedAt = Date()
        services[record.id] = record
        try? registry.upsert(record)

        killpg(pgid, SIGTERM)
        _ = try? registry.append(.stopping, service: record,
                             detail: "SIGTERM sent to process group \(pgid); SIGKILL in \(Int(config.stopGraceSec))s if it does not exit")
        pendingStops[record.id] = Date().addingTimeInterval(config.stopGraceSec)

        let id = record.id
        queue.asyncAfter(deadline: .now() + config.stopGraceSec) { [weak self] in
            self?.escalateStop(id: id, pgid: pgid, pid: pid)
        }
    }

    private func escalateStop(id: String, pgid: Int32, pid: Int32) {
        guard var record = services[id], pendingStops[id] != nil else { return }
        let table = ProcessTable.capture(includeListeners: false)
        let stillThere = table.process(pid) != nil || !table.processes(inGroup: pgid).isEmpty
        guard stillThere else { return }
        killpg(pgid, SIGKILL)
        _ = try? registry.append(.stopping, service: record,
                             detail: "did not exit within \(Int(config.stopGraceSec))s grace; SIGKILL sent to group \(pgid)")
        FleetLog.warn("SIGKILL sent to \(record.friendlyName) group \(pgid)")
        record.updatedAt = Date()
        services[id] = record
        try? registry.upsert(record)
    }

    /// Deliberately *not* run on the state queue: waiting for a process group to
    /// die must never stall the supervisor or the RPC surface.
    ///
    /// Restart re-executes the argv recorded at launch — it is not a general
    /// "run a command" entry point, which is why the UI can expose it safely.
    private func restart(_ idOrPrefix: String, reason: String) throws -> ServiceRecord {
        let (previous, grace) = try queue.sync { () -> (ServiceRecord, Double) in
            let resolved = try resolveID(idOrPrefix)
            guard let record = services[resolved] else { throw FleetError.notFound(idOrPrefix) }
            // Restart is stop-then-relaunch, and a claimed record fails at both
            // halves: we may not stop it, and its argv came off `ps` rather than
            // from a caller who declared it, so re-running it would be the app
            // inventing a service — the thing the README says it never does.
            try requireSignallable(record)
            if !record.state.isTerminal {
                beginStop(record, reason: reason, requestedBy: "restart")
            }
            return (record, config.stopGraceSec)
        }

        if !previous.state.isTerminal, let pgid = previous.pgid {
            let deadline = Date().addingTimeInterval(grace + 3)
            while Date() < deadline {
                let table = ProcessTable.capture(includeListeners: false)
                let groupGone = table.processes(inGroup: pgid).isEmpty
                let pidGone = previous.pid.flatMap { table.process($0) } == nil
                if groupGone && pidGone { break }
                usleep(250_000)
            }
        }

        return try queue.sync { () -> ServiceRecord in
            let request = LaunchRequest(friendlyName: previous.friendlyName,
                                        ownerAgent: previous.ownerAgent,
                                        purpose: previous.purpose,
                                        command: previous.command,
                                        cwd: previous.cwd,
                                        env: [:],
                                        declaredPorts: previous.declaredPorts,
                                        leaseTTLSec: previous.leaseTTLSec,
                                        budget: previous.budget,
                                        health: previous.health)
            var fresh = try launch(request)
            fresh.restartCount = previous.restartCount + 1
            services[fresh.id] = fresh
            try registry.upsert(fresh)
            try registry.append(.restarted, service: fresh,
                                detail: "restart #\(fresh.restartCount) of \(previous.shortID) — \(reason); previous pid \(previous.pid.map(String.init) ?? "unknown")")

            if var closed = services[previous.id], !closed.state.isTerminal {
                closed.state = .stopped
                closed.updatedAt = Date()
                services[closed.id] = closed
                try registry.upsert(closed)
            }
            return fresh
        }
    }

    /// Shared precondition for every signal we send: the pid must still exist and
    /// its start time must match what we recorded, or we are looking at a different
    /// process that merely inherited the number (threat model T2).
    private func verifiedTarget(_ record: ServiceRecord) throws -> (pid: Int32, pgid: Int32) {
        // Before "is this still the right process", the prior question: is it ours
        // to signal at all. Pause, resume and kill all resolve their target here.
        try requireSignallable(record)
        guard let pid = record.pid, let pgid = record.pgid, pgid > 1 else {
            throw FleetError.rejected("\(record.friendlyName) has no live process group")
        }
        guard pgid != getpgrp() else {
            throw FleetError.rejected("refusing to signal the controller's own process group")
        }
        let table = ProcessTable.capture(includeListeners: false)
        if let proc = table.process(pid), let signature = record.startSignature,
           proc.startSignature != signature {
            _ = try? registry.append(.pidReuseSuspected, service: record,
                                 detail: "pid \(pid) is now '\(proc.commandLine.prefix(80))'; no signal sent")
            throw FleetError.rejected("pid \(pid) has been reused by another process; no signal sent")
        }
        guard table.process(pid) != nil || !table.processes(inGroup: pgid).isEmpty else {
            throw FleetError.rejected("\(record.friendlyName) is no longer running")
        }
        return (pid, pgid)
    }

    private func pause(_ idOrPrefix: String) throws -> ServiceRecord {
        let resolved = try resolveID(idOrPrefix)
        guard var record = services[resolved] else { throw FleetError.notFound(idOrPrefix) }
        guard !record.state.isTerminal else {
            throw FleetError.rejected("\(record.friendlyName) is \(record.state.rawValue)")
        }
        guard record.state != .paused else { return record }
        let target = try verifiedTarget(record)

        killpg(target.pgid, SIGSTOP)
        record.state = .paused
        record.pausedAt = Date()
        record.updatedAt = Date()
        services[resolved] = record
        try registry.upsert(record)
        try registry.append(.paused, service: record,
                            detail: "SIGSTOP sent to process group \(target.pgid); it keeps its ports and memory")
        FleetLog.info("paused \(record.friendlyName) (\(record.shortID))")
        return record
    }

    private func resume(_ idOrPrefix: String) throws -> ServiceRecord {
        let resolved = try resolveID(idOrPrefix)
        guard var record = services[resolved] else { throw FleetError.notFound(idOrPrefix) }
        guard record.state == .paused else {
            throw FleetError.rejected("\(record.friendlyName) is not paused")
        }
        let target = try verifiedTarget(record)

        killpg(target.pgid, SIGCONT)
        let pausedFor = record.pausedAt.map { Date().timeIntervalSince($0) }
        record.state = .starting
        record.pausedAt = nil
        record.updatedAt = Date()
        services[resolved] = record
        try registry.upsert(record)
        try registry.append(.resumed, service: record,
                            detail: "SIGCONT sent to process group \(target.pgid)"
                                + (pausedFor.map { "; paused for \(Fmt.duration($0))" } ?? ""))
        return record
    }

    /// No grace period, by explicit request. Same verification as every other signal.
    private func forceKill(_ idOrPrefix: String, reason: String) throws -> ServiceRecord {
        let resolved = try resolveID(idOrPrefix)
        guard var record = services[resolved] else { throw FleetError.notFound(idOrPrefix) }
        guard !record.state.isTerminal else {
            throw FleetError.rejected("\(record.friendlyName) is already \(record.state.rawValue)")
        }
        let target = try verifiedTarget(record)

        try registry.append(.stopRequested, service: record, detail: "force kill: \(reason)")
        // A stopped process cannot die; wake it first or SIGKILL just queues.
        if record.state == .paused { killpg(target.pgid, SIGCONT) }
        killpg(target.pgid, SIGKILL)
        pendingStops[resolved] = Date()
        record.state = .stopping
        record.pausedAt = nil
        record.updatedAt = Date()
        services[resolved] = record
        try registry.upsert(record)
        try registry.append(.stopping, service: record,
                            detail: "SIGKILL sent directly to process group \(target.pgid) — no grace period")
        FleetLog.warn("force killed \(record.friendlyName) (\(record.shortID))")
        return record
    }

    private func resolveID(_ idOrPrefix: String) throws -> String {
        guard let record = try registry.resolve(idOrPrefix: idOrPrefix) else {
            throw FleetError.notFound("no service matching '\(idOrPrefix)'")
        }
        return record.id
    }

    private func tailLog(_ id: String, stream: String, maxBytes: Int) throws -> LogChunk {
        let serviceID = try resolveID(id)
        guard let record = services[serviceID] else { throw FleetError.notFound(id) }
        let path = stream == "err" ? record.stderrPath : record.stdoutPath
        guard let handle = FileHandle(forReadingAtPath: path) else {
            // "No log file yet" is true for a service that has just started and
            // false for a claimed one, which will never have a log file here: its
            // descriptors were wired up by whoever started it, long before we
            // adopted it. Saying "yet" would promise output that is never coming.
            return LogChunk(serviceID: serviceID, stream: stream, path: path, bytes: 0,
                            text: record.claimed
                                ? "(claimed, not launched — its output goes wherever it was started, "
                                  + "not through the controller)"
                                : "(no log file yet)",
                            truncated: false)
        }
        defer { try? handle.close() }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let total = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        let offset = max(0, total - maxBytes)
        try? handle.seek(toOffset: UInt64(offset))
        let data = (try? handle.readToEnd()) ?? Data()
        return LogChunk(serviceID: serviceID, stream: stream, path: path, bytes: total,
                        text: String(data: data, encoding: .utf8) ?? "(binary output)",
                        truncated: offset > 0)
    }

    // MARK: - Snapshot

    private func makeSnapshot() -> Snapshot {
        let all = services.values.sorted { $0.startedAt > $1.startedAt }
        // Read once and share: the attention rules need the same history the UI shows.
        let recent = (try? registry.events(limit: 60)) ?? []
        return Snapshot(generatedAt: Date(),
                        daemon: daemon,
                        services: all,
                        unmanaged: unmanagedList,
                        devices: deviceList,
                        attention: computeAttention(all, recentEvents: recent),
                        recentEvents: recent,
                        messages: (try? registry.messages(limit: 60)) ?? [],
                        external: externalList,
                        sessions: sessionList)
    }

    /// A crash loop in the controller itself is only news while it is recent, and one
    /// abnormal exit is not yet a pattern — two inside this window is.
    private static let daemonCrashWindow: TimeInterval = 6 * 3600
    private static let daemonCrashThreshold = 2

    private func computeAttention(_ all: [ServiceRecord], recentEvents: [ServiceEvent]) -> [AttentionItem] {
        var items: [AttentionItem] = []
        let staleTolerance = config.supervisorTickSec * config.staleTickFactor

        // The controller restarting leaves no service row behind, so without this item a
        // crash loop is invisible in a UI built entirely out of services: 136 starts
        // against 43 clean stops was only discoverable by reading the database by hand.
        let cutoff = Date().addingTimeInterval(-Self.daemonCrashWindow)
        let daemonCrashes = recentEvents.filter { $0.kind == .daemonCrashed && $0.ts >= cutoff }
        if daemonCrashes.count >= Self.daemonCrashThreshold, let oldest = daemonCrashes.last {
            items.append(AttentionItem(id: "daemon-crashloop", severity: .critical,
                                       title: "The controller has been restarting",
                                       detail: "\(daemonCrashes.count) abnormal exits since \(Fmt.relative(oldest.ts))"
                                           + " — check ~/Library/Logs/FleetConsole/fleetd.log",
                                       since: oldest.ts))
        }

        for record in all where !record.state.isTerminal {
            switch record.state {
            case .unhealthy:
                items.append(AttentionItem(id: "unhealthy-\(record.id)", severity: .critical,
                                           title: "\(record.friendlyName): health check failing",
                                           detail: record.evidence.healthDetail
                                                ?? "failed \(record.consecutiveHealthFailures)× in a row",
                                           serviceID: record.id, since: record.updatedAt))
            case .expired:
                // Both halves of this detail are false for a claimed record, and
                // the second one dangerously so: "controller is reaping it" would
                // have you stop watching a process nobody is going to stop.
                items.append(AttentionItem(id: "expired-\(record.id)", severity: .critical,
                                           title: "\(record.friendlyName): lease expired",
                                           detail: record.isSignallableByController
                                               ? "owner \(record.ownerAgent) stopped renewing; controller is reaping it"
                                               : "owner \(record.ownerAgent) stopped renewing. Claimed, not launched — "
                                                 + "nothing is reaping it. Renew it or stop it where you started it",
                                           serviceID: record.id, since: record.leaseExpiresAt))
            case .expiring:
                items.append(AttentionItem(id: "expiring-\(record.id)", severity: .warning,
                                           title: "\(record.friendlyName): lease expires in \(Fmt.duration(record.leaseRemaining))",
                                           detail: record.isSignallableByController
                                               ? "renew it or it will be stopped automatically"
                                               : "renew it, or the record expires and stops being supervised — "
                                                 + "the process itself keeps running either way",
                                           serviceID: record.id, since: record.updatedAt))
            case .degraded:
                items.append(AttentionItem(id: "degraded-\(record.id)", severity: .warning,
                                           title: "\(record.friendlyName): \(record.budgetBreaches.first ?? "degraded")",
                                           detail: record.budgetBreaches.joined(separator: "; "),
                                           serviceID: record.id, since: record.updatedAt))
            default:
                if record.evidence.isStale(tolerance: staleTolerance) {
                    items.append(AttentionItem(id: "stale-\(record.id)", severity: .warning,
                                               title: "\(record.friendlyName): status is stale",
                                               detail: "last verified \(Fmt.relative(record.evidence.checkedAt))",
                                               serviceID: record.id, since: record.evidence.checkedAt ?? record.updatedAt))
                }
            }
        }

        // Only the most recent crash per name, and only while it is still news.
        // Five identical "crashed" rows from five restart attempts is noise that
        // buries the one line that matters.
        var crashesSeen = Set<String>()
        for record in all.filter({ $0.state == .crashed }).sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard Date().timeIntervalSince(record.updatedAt) < config.crashAttentionSec else { continue }
            guard crashesSeen.insert(record.friendlyName).inserted else { continue }
            let exit = record.lastExitCode.map { $0 < 0 ? "killed by signal \(-$0)" : "exit code \($0)" }
                ?? "no exit status recorded"
            items.append(AttentionItem(id: "crashed-\(record.id)", severity: .critical,
                                       title: "\(record.friendlyName) crashed",
                                       detail: "\(exit) · \(Fmt.relative(record.updatedAt))",
                                       serviceID: record.id, since: record.updatedAt))
        }

        // Unmanaged processes are a *state*, not an incident. Only two kinds are
        // worth interrupting for: something that leaked out of our own control, and
        // something that has just appeared. A listener that has been up for hours is
        // part of the furniture — it stays visible in the Services list and in the
        // dashboard, but it does not sit in "Needs attention" forever nagging.
        for process in unmanagedList {
            let ports = process.ports.isEmpty ? "" : " on \(Fmt.ports(process.ports))"
            if process.formerServiceID != nil {
                items.append(AttentionItem(id: "leaked-\(process.id)", severity: .critical,
                                           title: "Leaked: \(process.command)\(ports)",
                                           detail: "started through the controller but outlived its record · pid \(process.pid)",
                                           unmanagedID: process.id, since: process.firstSeen))
            } else if Date().timeIntervalSince(process.firstSeen) < config.unmanagedGraceSec {
                items.append(AttentionItem(id: "unmanaged-\(process.id)", severity: .warning,
                                           title: "New unmanaged process: \(process.command)\(ports)",
                                           detail: "\(process.reason.label) · pid \(process.pid) · first seen \(Fmt.relative(process.firstSeen))",
                                           unmanagedID: process.id, since: process.firstSeen))
            }
        }

        for device in deviceList where device.health == .unreachable {
            items.append(AttentionItem(id: "device-\(device.id)", severity: .warning,
                                       title: "\(device.name) unreachable",
                                       detail: "last reachable \(Fmt.relative(device.lastReachableAt))",
                                       since: device.evidence.checkedAt ?? Date()))
        }

        return items.sorted {
            ($0.severity == .critical ? 0 : 1, $0.since.timeIntervalSince1970)
                < ($1.severity == .critical ? 0 : 1, $1.since.timeIntervalSince1970)
        }
    }

    /// Always hops onto the state queue asynchronously: callers may or may not
    /// already be running on it, and `queue.sync` from within the queue deadlocks.
    private func broadcastSnapshot() {
        queue.async { [weak self] in self?.broadcastLocked() }
    }

    /// Must be called on `queue`.
    private func broadcastLocked() {
        guard !subscribers.isEmpty else { return }
        // Coalesce. Ticks, health transitions and device probes all broadcast, and every
        // queued closure pins a whole Snapshot (all services, 60 events, 60 messages,
        // devices, sessions). Behind a subscriber that is not draining, those used to
        // pile up on `broadcastQueue` without bound. At most one write is in flight and
        // at most one is pending, and the pending one is built fresh when its turn comes
        // — a newer snapshot always supersedes an older one.
        guard !broadcastInFlight else {
            broadcastPending = true
            return
        }
        broadcastInFlight = true
        dispatchBroadcast(makeSnapshot())
    }

    /// Must be called on `queue`, with `broadcastInFlight` already set.
    private func dispatchBroadcast(_ snapshot: Snapshot) {
        let targets = Array(subscribers.values)
        broadcastQueue.async { [weak self] in
            if let data = try? Codec.encode(RPCResponse(ok: true, snapshot: snapshot)) {
                for conn in targets {
                    do {
                        try conn.writeLine(data)
                    } catch {
                        // The write can now time out as well as fail outright; either way
                        // this subscriber is not keeping up and is dropped rather than
                        // allowed to stall every other one.
                        FleetLog.debug("dropping subscriber: \(error.localizedDescription)")
                        conn.close()
                        self?.queue.async { self?.subscribers.removeValue(forKey: ObjectIdentifier(conn)) }
                    }
                }
            }
            self?.queue.async {
                guard let self else { return }
                let pending = self.broadcastPending
                self.broadcastPending = false
                if pending, !self.subscribers.isEmpty {
                    self.dispatchBroadcast(self.makeSnapshot())
                } else {
                    self.broadcastInFlight = false
                }
            }
        }
    }

    // MARK: - Connection handling

    private func handleConnection(_ conn: SocketConnection) {
        defer {
            queue.sync { _ = subscribers.removeValue(forKey: ObjectIdentifier(conn)) }
            conn.close()
        }
        while true {
            let line: Data?
            do {
                line = try conn.readLine()
            } catch {
                FleetLog.debug("connection read error: \(error.localizedDescription)")
                return
            }
            guard let line else { return }

            let request: RPCRequest
            do {
                request = try Codec.decode(RPCRequest.self, from: line)
            } catch {
                try? conn.writeJSON(RPCResponse.failure("malformed request: \(error.localizedDescription)"))
                continue
            }

            if request.op == .subscribe {
                queue.sync { subscribers[ObjectIdentifier(conn)] = conn }
                let snapshot = queue.sync { makeSnapshot() }
                try? conn.writeJSON(RPCResponse(ok: true, snapshot: snapshot))
                continue    // further pushes come from broadcastSnapshot()
            }

            let response = handle(request)
            do {
                try conn.writeJSON(response)
            } catch {
                return
            }
        }
    }

    private func handle(_ request: RPCRequest) -> RPCResponse {
        switch request.op {
        case .ping:
            return RPCResponse(ok: true, daemon: queue.sync { daemon })

        case .snapshot:
            return RPCResponse(ok: true, snapshot: queue.sync { makeSnapshot() })

        case .subscribe:
            return RPCResponse.failure("subscribe is handled per-connection")

        case .launch:
            guard let launchRequest = request.launch else {
                return .failure("launch requires a request body")
            }
            do {
                let record = try queue.sync { try launch(launchRequest) }
                broadcastSnapshot()
                return RPCResponse(ok: true, service: record)
            } catch {
                return .failure(error.localizedDescription)
            }

        case .renew:
            guard let id = request.serviceID else { return .failure("renew requires a service id") }
            do {
                let record = try queue.sync { try renew(id, ttl: request.ttlSec) }
                broadcastSnapshot()
                return RPCResponse(ok: true, service: record)
            } catch {
                return .failure(error.localizedDescription)
            }

        case .stop:
            guard let id = request.serviceID else { return .failure("stop requires a service id") }
            do {
                let record: ServiceRecord = try queue.sync {
                    let resolved = try resolveID(id)
                    guard let record = services[resolved] else { throw FleetError.notFound(id) }
                    guard !record.state.isTerminal else {
                        throw FleetError.rejected("\(record.friendlyName) is already \(record.state.rawValue)")
                    }
                    try requireSignallable(record)
                    beginStop(record, reason: request.reason ?? "requested by operator",
                              requestedBy: "operator")
                    return services[resolved] ?? record
                }
                broadcastSnapshot()
                return RPCResponse(ok: true, service: record)
            } catch {
                return .failure(error.localizedDescription)
            }

        case .restart:
            guard let id = request.serviceID else { return .failure("restart requires a service id") }
            do {
                let record = try restart(id, reason: request.reason ?? "requested by operator")
                broadcastSnapshot()
                return RPCResponse(ok: true, service: record)
            } catch {
                return .failure(error.localizedDescription)
            }

        case .events:
            do {
                let events = try queue.sync { () -> [ServiceEvent] in
                    // An unknown id must fail loudly. Silently widening to the global
                    // log would answer a question nobody asked.
                    let resolved = try request.serviceID.map { try resolveID($0) }
                    return try registry.events(serviceID: resolved,
                                               limit: min(request.limit ?? 200, 2000))
                }
                return RPCResponse(ok: true, events: events)
            } catch {
                return .failure(error.localizedDescription)
            }

        case .logs:
            guard let id = request.serviceID else { return .failure("logs requires a service id") }
            do {
                let chunk = try queue.sync {
                    try tailLog(id, stream: request.stream ?? "out",
                                maxBytes: min(request.maxBytes ?? 64_000, 1_000_000))
                }
                return RPCResponse(ok: true, logs: chunk)
            } catch {
                return .failure(error.localizedDescription)
            }

        case .claim:
            guard let target = request.unmanagedID,
                  !target.trimmingCharacters(in: .whitespaces).isEmpty else {
                return .failure("claim requires an unmanaged process id or a pid")
            }
            do {
                // Captured off the state queue, like every other process probe in
                // this file, and passed in so the verification and the record are
                // built from one table rather than from two moments.
                let table = ProcessTable.capture()
                let record = try queue.sync {
                    try claim(unmanagedID: target,
                              friendlyName: request.friendlyName,
                              owner: request.agent,
                              purpose: request.purpose,
                              ttl: request.ttlSec,
                              table: table)
                }
                broadcastSnapshot()
                return RPCResponse(ok: true, service: record)
            } catch {
                return .failure(error.localizedDescription)
            }

        case .reconcile:
            let table = ProcessTable.capture()
            queue.sync { runReconcile(table: table) }
            broadcastSnapshot()
            return RPCResponse(ok: true, snapshot: queue.sync { makeSnapshot() })

        case .refreshDevices:
            probeDevices()
            return RPCResponse(ok: true, snapshot: queue.sync { makeSnapshot() })

        case .pause, .resume, .kill:
            guard let id = request.serviceID else { return .failure("\(request.op.rawValue) requires a service id") }
            do {
                let record = try queue.sync { () -> ServiceRecord in
                    switch request.op {
                    case .pause: return try pause(id)
                    case .resume: return try resume(id)
                    default: return try forceKill(id, reason: request.reason ?? "requested by operator")
                    }
                }
                broadcastSnapshot()
                return RPCResponse(ok: true, service: record)
            } catch {
                return .failure(error.localizedDescription)
            }

        case .postMessage:
            guard let agent = request.agent, !agent.isEmpty else {
                return .failure("a message needs --agent")
            }
            guard let body = request.body, !body.trimmingCharacters(in: .whitespaces).isEmpty else {
                return .failure("a message needs --message")
            }
            do {
                let stored = try queue.sync { () -> AgentMessage in
                    let service = try request.serviceID.flatMap { try registry.resolve(idOrPrefix: $0) }
                    let message = AgentMessage(agent: agent,
                                               serviceID: service?.id,
                                               serviceName: service?.friendlyName,
                                               kind: request.kind ?? .status,
                                               body: body,
                                               needsReply: request.needsReply ?? false)
                    let saved = try registry.post(message)
                    try registry.append(.messagePosted, service: service,
                                        detail: "\(agent) [\(saved.kind.rawValue)]"
                                            + (saved.needsReply ? " (awaiting reply)" : "")
                                            + ": \(body.prefix(160))")
                    return saved
                }
                broadcastSnapshot()
                return RPCResponse(ok: true, message: stored)
            } catch {
                return .failure(error.localizedDescription)
            }

        case .messages:
            do {
                let list = try queue.sync {
                    try registry.messages(agent: request.agent,
                                          limit: min(request.limit ?? 100, 1000),
                                          unansweredOnly: request.unansweredOnly ?? false)
                }
                return RPCResponse(ok: true, messages: list)
            } catch {
                return .failure(error.localizedDescription)
            }

        case .reply:
            guard let messageID = request.messageID else { return .failure("reply requires a message id") }
            guard let body = request.body, !body.trimmingCharacters(in: .whitespaces).isEmpty else {
                return .failure("reply requires text")
            }
            do {
                let updated = try queue.sync { () -> AgentMessage in
                    let answered = try registry.reply(to: messageID, with: body)
                    try registry.append(.messageAnswered, service: nil,
                                        detail: "answered \(answered.agent) message \(messageID): \(body.prefix(160))")
                    return answered
                }
                broadcastSnapshot()
                return RPCResponse(ok: true, message: updated)
            } catch {
                return .failure(error.localizedDescription)
            }

        case .markSeen:
            do {
                try queue.sync {
                    let ids: [Int64]
                    if let single = request.messageID {
                        ids = [single]
                    } else {
                        ids = try registry.messages(limit: 200).filter { $0.seenAt == nil }.map(\.id)
                    }
                    try registry.markSeen(ids)
                }
                broadcastSnapshot()
                return RPCResponse(ok: true)
            } catch {
                return .failure(error.localizedDescription)
            }

        case .ignoreCommand:
            guard let command = request.command,
                  !command.trimmingCharacters(in: .whitespaces).isEmpty else {
                return .failure("ignoreCommand requires a command name")
            }
            do {
                try queue.sync {
                    guard !config.ignoredListenerCommands.contains(command) else { return }
                    config.ignoredListenerCommands.append(command)
                    try config.save()
                    try registry.append(.registered, service: nil,
                                        detail: "'\(command)' added to the expected-listener allow-list by the operator")
                }
                let table = ProcessTable.capture()
                queue.sync { runReconcile(table: table) }
                broadcastSnapshot()
                return RPCResponse(ok: true, snapshot: queue.sync { makeSnapshot() })
            } catch {
                return .failure("could not update config: \(error.localizedDescription)")
            }

        case .prune:
            do {
                // Terminal service rows only. The event log is append-only and is
                // never touched by this — the audit trail outlives the records.
                let age = request.ttlSec ?? 3600
                try queue.sync {
                    try registry.pruneTerminated(olderThan: age)
                    let keep = Set(try registry.services().map(\.id))
                    services = services.filter { keep.contains($0.key) }
                }
                broadcastSnapshot()
                return RPCResponse(ok: true, snapshot: queue.sync { makeSnapshot() })
            } catch {
                return .failure(error.localizedDescription)
            }

        case .reloadConfig:
            do {
                let fresh = try FleetConfig.load()
                queue.sync {
                    config = fresh
                    daemon.tickIntervalSec = fresh.supervisorTickSec
                }
                probeDevices()
                return RPCResponse(ok: true, snapshot: queue.sync { makeSnapshot() })
            } catch {
                return .failure("could not reload config: \(error.localizedDescription)")
            }
        }
    }
}

private extension String {
    /// An empty string is not a name, an owner or a purpose. Collapsing it to nil
    /// here is what lets `claim` fall through to its defaults with `??` instead of
    /// filing a record whose `friendlyName` is "".
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
