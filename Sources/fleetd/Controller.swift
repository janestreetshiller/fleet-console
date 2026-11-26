import Foundation
import Darwin
import FleetCore

final class Controller: @unchecked Sendable {
    static let version = "1.1.0"

    let queue = DispatchQueue(label: "com.fleetconsole.controller")
    private let workQueue = DispatchQueue(label: "com.fleetconsole.work", attributes: .concurrent)
    private let broadcastQueue = DispatchQueue(label: "com.fleetconsole.broadcast")

    let registry: Registry
    var config: FleetConfig
    private var configWarning: String?

    var services: [String: ServiceRecord] = [:]
    private var unmanagedList: [UnmanagedProcess] = []
    private var externalList: [ExternalService] = []
    private var sessionList: [AgentSession] = []
    private var deviceList: [DeviceRecord] = []
    private var tailscale: TailscaleStatus?

    var subscribers: [ObjectIdentifier: SocketConnection] = [:]
    var daemon: DaemonInfo

    private var broadcastInFlight = false
    private var broadcastPending = false

    private var pendingStops: [String: Date] = [:]
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
            FleetLog.warn("rejected connection from uid \(uid)")
            guard let self else { return }
            self.queue.async {
                _ = try? self.registry.append(.rejectedPeer, service: nil,
                                              detail: "connection from uid \(uid) refused (daemon uid \(geteuid()))")
            }
        }
        try server.start()
        self.server = server
        FleetLog.info("listening on \(FleetPaths.socket.path)")

        startTicking()

        server.run { [weak self] conn in
            self?.handleConnection(conn)
        }
    }

    func shutdown() {
        tickTimer?.cancel()
        server?.stop()
        queue.sync {
            _ = try? registry.append(.daemonStopping, service: nil,
                                 detail: "controller stopping; \(services.values.filter { !$0.state.isTerminal }.count) managed services left running")
            registry.close()
        }
        StopMarker.clear()
        FleetLog.info("controller stopped")
    }

    private func recordPreviousGenerationCrash() throws {
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
                record.evidence.leaderVerifiedAt = record.leaderVerification(in: table)
                record.evidence.portScanRan = false
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
                exitCode = -(status & 0x7f)
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
        record.evidence.leaderVerifiedAt = nil
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

    private func tick() {
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
            guard !table.processProbeFailed else {
                for (id, record) in self.services where record.evidence.leaderVerifiedAt != nil {
                    self.services[id]?.evidence.leaderVerifiedAt = nil
                }
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
            guard table.capturedAt.timeIntervalSince(record.startedAt) > 0.25 else { continue }

            let alive = isAlive(record, in: table)
            record.evidence.checkedAt = now
            record.evidence.processExists = alive
            record.evidence.leaderVerifiedAt = record.leaderVerification(in: table)
            record.evidence.portScanRan = false

            if !alive {
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

            if record.state == .stopping {
                if let pgid = record.pgid {
                    record.evidence.listeningPorts = table.listeningPorts(inGroup: pgid)
                    record.evidence.portScanRan = !table.listenerProbeFailed
                    record.resources = table.resourceUsage(inGroup: pgid)
                }
                record.updatedAt = now
                services[record.id] = record
                try? registry.upsert(record)
                continue
            }

            guard let pgid = record.pgid else {
                services[record.id] = record
                try? registry.upsert(record)
                continue
            }
            record.evidence.listeningPorts = table.listeningPorts(inGroup: pgid)
            record.evidence.portScanRan = !table.listenerProbeFailed
            record.resources = table.resourceUsage(inGroup: pgid)

            record.cpuHistory.append(record.resources.cpuPct ?? 0)
            record.memHistory.append(record.resources.memMB ?? 0)
            if record.cpuHistory.count > ServiceRecord.historyLimit {
                record.cpuHistory.removeFirst(record.cpuHistory.count - ServiceRecord.historyLimit)
            }
            if record.memHistory.count > ServiceRecord.historyLimit {
                record.memHistory.removeFirst(record.memHistory.count - ServiceRecord.historyLimit)
            }

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
                record.reapedForExpiry = record.isSignallableByController
                record.updatedAt = now
                services[record.id] = record
                try? registry.upsert(record)
                guard record.isSignallableByController else {
                    FleetLog.info("claimed record \(record.friendlyName) (\(record.shortID)) expired: \(reap)")
                    continue
                }
                FleetLog.info("reaping \(record.friendlyName) (\(record.shortID)): \(reap)")
                beginStop(record, reason: reap, requestedBy: "controller")
                continue
            }

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
                    let consequence = record.isSignallableByController
                        ? "renew or it will be stopped"
                        : "renew to keep the claim current; the controller will not signal it"
                    _ = try? registry.append(.leaseExpiring, service: record,
                                             detail: "lease expires in \(Fmt.duration(remaining)) — \(consequence)")
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

    private func checkForEscapedPorts(_ record: ServiceRecord, table: ProcessTable) {
        let survivors = table.listeners.filter { record.declaredPorts.contains($0.port) }
        guard !survivors.isEmpty else { return }
        let detail = survivors
            .map { ":\($0.port) still held by \($0.command) pid \($0.pid)" }
            .joined(separator: "; ")
        _ = try? registry.append(.reapIncomplete, service: record, detail: detail)
        FleetLog.warn("reap incomplete for \(record.friendlyName): \(detail)")
    }

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

        if previous != outcome.passed {
            _ = try? registry.append(outcome.passed ? .healthPassed : .healthFailed, service: record,
                                 detail: outcome.detail + String(format: " (%.0f ms)", outcome.latencyMs))
        } else if !outcome.passed && record.consecutiveHealthFailures == record.health.failureThreshold {
            _ = try? registry.append(.healthFailed, service: record,
                                 detail: "failed \(record.consecutiveHealthFailures)× in a row: \(outcome.detail)")
        }
        broadcastSnapshot()
    }

    func runReconcile(table: ProcessTable) {
        guard !table.probeFailed else {
            FleetLog.warn("skipping reconcile: process probe failed"
                          + (table.processProbeFailed ? " (ps)" : "")
                          + (table.listenerProbeFailed ? " (lsof)" : "")
                          + "; keeping the previous unmanaged set")
            return
        }
        let inputs = Reconciler.Inputs(table: table, config: config, services: Array(services.values))
        let tools = Reconciler.externalServices(inputs)
        externalList = tools.services
        let found = Reconciler.scan(inputs, claimedPIDs: tools.claimedPIDs)
        sessionList = SessionScanner.scan(table: table)
        let known = Set(unmanagedList.map(\.id))
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

    func probeDevices() {
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

    func launch(_ request: LaunchRequest) throws -> ServiceRecord {
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
                                   envKeys: request.env.keys.sorted(),
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

    func claim(unmanagedID: String, friendlyName: String?, owner: String?,
                       purpose: String?, ttl: Double?, table: ProcessTable) throws -> ServiceRecord {
        guard !table.processProbeFailed else {
            throw FleetError.rejected("the process probe failed; nothing can be verified this moment")
        }

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
        let observedPorts = table.listeningPorts(inGroup: proc.pgid)
        let ports = known?.ports ?? observedPorts

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
                                   startedAt: Reconciler.parseStartTime(proc.startSignature)
                                       ?? known?.firstSeen ?? Date(),
                                   leaseExpiresAt: Date().addingTimeInterval(leaseTTL),
                                   leaseTTLSec: leaseTTL,
                                   state: .running,
                                   evidence: Evidence(processExists: true,
                                                      listeningPorts: observedPorts,
                                                      portScanRan: !table.listenerProbeFailed,
                                                      checkedAt: Date()),
                                   resources: table.resourceUsage(inGroup: proc.pgid))
        record.evidence.leaderVerifiedAt = record.leaderVerification(in: table)
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

        unmanagedList.removeAll { $0.pid == pid }
        return record
    }

    func requireSignallable(_ record: ServiceRecord) throws {
        if let refusal = record.signalRefusal {
            throw FleetError.rejected(refusal)
        }
    }

    func renew(_ id: String, ttl: Double?) throws -> ServiceRecord {
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

    func beginStop(_ record: ServiceRecord, reason: String, requestedBy: String) {
        var record = record
        guard record.isSignallableByController else {
            _ = try? registry.append(.rejectedLaunch, service: record,
                                 detail: "\(requestedBy) asked to stop a claimed record: \(reason). "
                                     + (record.signalRefusal ?? ""))
            FleetLog.warn("refusing to stop claimed record \(record.friendlyName) (\(record.shortID))")
            return
        }
        guard let pid = record.pid, let pgid = record.pgid, pgid > 1 else {
            record.evidence.leaderVerifiedAt = nil
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
        record.evidence.leaderVerifiedAt = record.leaderVerification(in: table)
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

    func restart(_ idOrPrefix: String, reason: String) throws -> ServiceRecord {
        let (previous, grace) = try queue.sync { () -> (ServiceRecord, Double) in
            let resolved = try resolveID(idOrPrefix)
            guard let record = services[resolved] else { throw FleetError.notFound(idOrPrefix) }
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
                closed.evidence.leaderVerifiedAt = nil
                closed.updatedAt = Date()
                services[closed.id] = closed
                try registry.upsert(closed)
            }
            return fresh
        }
    }

    private func verifiedTarget(_ record: ServiceRecord) throws -> (pid: Int32, pgid: Int32) {
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

    func pause(_ idOrPrefix: String) throws -> ServiceRecord {
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

    func resume(_ idOrPrefix: String) throws -> ServiceRecord {
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

    func forceKill(_ idOrPrefix: String, reason: String) throws -> ServiceRecord {
        let resolved = try resolveID(idOrPrefix)
        guard var record = services[resolved] else { throw FleetError.notFound(idOrPrefix) }
        guard !record.state.isTerminal else {
            throw FleetError.rejected("\(record.friendlyName) is already \(record.state.rawValue)")
        }
        let target = try verifiedTarget(record)

        try registry.append(.stopRequested, service: record, detail: "force kill: \(reason)")
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

    func resolveID(_ idOrPrefix: String) throws -> String {
        guard let record = try registry.resolve(idOrPrefix: idOrPrefix) else {
            throw FleetError.notFound("no service matching '\(idOrPrefix)'")
        }
        return record.id
    }

    func tailLog(_ id: String, stream: String, maxBytes: Int) throws -> LogChunk {
        let serviceID = try resolveID(id)
        guard let record = services[serviceID] else { throw FleetError.notFound(id) }
        let path = stream == "err" ? record.stderrPath : record.stdoutPath
        guard let handle = FileHandle(forReadingAtPath: path) else {
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

    func makeSnapshot() -> Snapshot {
        let all = services.values.sorted { $0.startedAt > $1.startedAt }
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

    private static let daemonCrashWindow: TimeInterval = 6 * 3600
    private static let daemonCrashThreshold = 2

    private func computeAttention(_ all: [ServiceRecord], recentEvents: [ServiceEvent]) -> [AttentionItem] {
        var items: [AttentionItem] = []
        let staleTolerance = config.supervisorTickSec * config.staleTickFactor

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

    func broadcastSnapshot() {
        queue.async { [weak self] in self?.broadcastLocked() }
    }

    private func broadcastLocked() {
        guard !subscribers.isEmpty else { return }
        guard !broadcastInFlight else {
            broadcastPending = true
            return
        }
        broadcastInFlight = true
        dispatchBroadcast(makeSnapshot())
    }

    private func dispatchBroadcast(_ snapshot: Snapshot) {
        let targets = Array(subscribers.values)
        broadcastQueue.async { [weak self] in
            guard let self else { return }
            if let data = try? Codec.encode(RPCResponse(ok: true, snapshot: snapshot)) {
                for conn in targets {
                    do {
                        try conn.writeLine(data)
                    } catch {
                        FleetLog.debug("dropping subscriber: \(error.localizedDescription)")
                        conn.close()
                        self.queue.async { self.subscribers.removeValue(forKey: ObjectIdentifier(conn)) }
                    }
                }
            }
            self.queue.async {
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

}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
