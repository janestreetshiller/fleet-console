import Foundation
import SwiftUI
import FleetCore

/// One observable box per service. Rows observe *their own* record, so a snapshot
/// that changes one service's CPU number re-renders one row, not the whole list.
@Observable
final class ServiceRow: Identifiable {
    let id: String
    var record: ServiceRecord

    init(_ record: ServiceRecord) {
        self.id = record.id
        self.record = record
    }
}

@Observable
final class DeviceRow: Identifiable {
    let id: String
    var record: DeviceRecord

    init(_ record: DeviceRecord) {
        self.id = record.id
        self.record = record
    }
}

@Observable
@MainActor
final class AppModel {
    // Membership-level state: reassigned only when the *set* changes.
    private(set) var serviceRows: [ServiceRow] = []
    private(set) var deviceRows: [DeviceRow] = []
    private(set) var unmanaged: [UnmanagedProcess] = []
    private(set) var attention: [AttentionItem] = []
    private(set) var recentEvents: [ServiceEvent] = []

    var daemon: DaemonInfo?
    var connected = false
    var connectionError: String?
    var agentRegistered = false
    var lastSnapshotAt: Date?
    /// Local monotonic receipt time, independent of the daemon's wall clock.
    /// Cleared on connection transitions so a reconnect cannot reuse old evidence.
    private(set) var lastSnapshotReceivedUptime: TimeInterval?
    var actionError: String?
    var busyServiceIDs: Set<String> = []

    /// `config.json`, watched. Every section toggle, cadence and feature flag
    /// resolves here, so no view invents its own answer. Built first because the
    /// probes below take their intervals from it.
    let settings = Settings()

    let network: NetworkMonitor
    let actions = NetworkActions()
    /// Licensing and the trial clock. Declared before the probes that gate on
    /// it (`system` reads its answer every sample), so property order is also
    /// the dependency order. See FleetCore/License.swift.
    let license = LicenseManager()
    let system: SystemMonitor
    let storage = StorageScanner()
    let breakdown = StorageBreakdown()
    let processes: ProcessInventory
    let hosts = HostProbe()
    /// Today's agent spend. Sampled on its own slow cadence rather than the
    /// snapshot's — see `AgentCostProbe` — and only when the feature is on.
    let agentCost = AgentCostProbe()

    /// Drives lease countdowns and "x ago" labels without touching the data model.
    var clockTick: Int = 0

    /// Which popover section the next opening should land on, set by the
    /// status item's dropdown and cleared by the popover once it has moved.
    /// `nil` means no one asked, and the popover falls back to its own rule.
    var requestedSection: FleetSection?

    // Nonisolated so `deinit` can invalidate it; nothing observes this handle.
    @ObservationIgnored nonisolated(unsafe) private var clockTimer: Timer?
    private var didInitialLoad = false

    init() {
        // Cadences come from config, clamped there. Read once at construction:
        // a live interval change would mean tearing down and rebuilding the two
        // timers, and the honest cost of editing a sampling rate is a relaunch.
        let intervals = settings.intervals
        network = NetworkMonitor(interval: intervals.clampedNetworkRefresh)
        system = SystemMonitor { [license] feature in license.isUnlocked(feature) }
        processes = ProcessInventory(interval: intervals.clampedProcessSample)

        DaemonClient.shared.startSubscription { [weak self] snapshot in
            self?.apply(snapshot)
        } onConnection: { [weak self] connected, error in
            guard let self else { return }
            self.connected = connected
            self.connectionError = connected ? nil : error
            self.lastSnapshotReceivedUptime = nil
            if !connected {
                self.agentRegistered = DaemonClient.shared.agentIsRegistered()
            }
        }
        network.refresh()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.clockTick &+= 1 }
        }
    }

    /// The run loop holds the timer even though the closure is weak, so it has to
    /// be invalidated here or a per-view instance would strand a live tick.
    deinit {
        clockTimer?.invalidate()
    }

    // MARK: - Snapshot application

    func apply(_ snapshot: Snapshot) {
        daemon = snapshot.daemon
        lastSnapshotAt = snapshot.generatedAt
        lastSnapshotReceivedUptime = ProcessInfo.processInfo.systemUptime

        // Services: update in place; only reassign the array when membership changes.
        let incoming = snapshot.services
        var existing = Dictionary(uniqueKeysWithValues: serviceRows.map { ($0.id, $0) })
        var rebuilt: [ServiceRow] = []
        var membershipChanged = incoming.count != serviceRows.count
        for record in incoming {
            if let row = existing.removeValue(forKey: record.id) {
                if row.record != record { row.record = record }
                rebuilt.append(row)
            } else {
                rebuilt.append(ServiceRow(record))
                membershipChanged = true
            }
        }
        if !existing.isEmpty { membershipChanged = true }
        if membershipChanged || zip(rebuilt, serviceRows).contains(where: { $0.0 !== $0.1 }) {
            serviceRows = rebuilt
        }

        var existingDevices = Dictionary(uniqueKeysWithValues: deviceRows.map { ($0.id, $0) })
        var rebuiltDevices: [DeviceRow] = []
        var devicesChanged = snapshot.devices.count != deviceRows.count
        for record in snapshot.devices {
            if let row = existingDevices.removeValue(forKey: record.id) {
                if row.record != record { row.record = record }
                rebuiltDevices.append(row)
            } else {
                rebuiltDevices.append(DeviceRow(record))
                devicesChanged = true
            }
        }
        if !existingDevices.isEmpty { devicesChanged = true }
        if devicesChanged { deviceRows = rebuiltDevices }

        let agents = snapshot.agentSummaries
        if agentSummaries != agents { agentSummaries = agents }
        let profiles = snapshot.agentProfiles
        if agentProfiles != profiles { agentProfiles = profiles }
        if recentMessages != snapshot.messages {
            let previouslyKnown = Set(recentMessages.map(\.id))
            recentMessages = snapshot.messages
            // Notify once, for messages we have not seen before.
            let fresh = snapshot.messages.filter { !previouslyKnown.contains($0.id) && $0.seenAt == nil }
            if !didInitialLoad {
                didInitialLoad = true          // don't replay the backlog on launch
            } else {
                for message in fresh { Notifier.post(message) }
            }
        }
        if externalServices != snapshot.external { externalServices = snapshot.external }
        if sessions != snapshot.sessions { sessions = snapshot.sessions }
        if unmanaged != snapshot.unmanaged { unmanaged = snapshot.unmanaged }
        if attention != snapshot.attention { attention = snapshot.attention }
        if recentEvents != snapshot.recentEvents { recentEvents = snapshot.recentEvents }

        // Rides the snapshot tick as a heartbeat only: the probe throttles
        // itself, so this asks far more often than it scans.
        if settings.features.showAgentSpend { agentCost.refresh() }
    }

    // MARK: - Derived state

    var activeServices: [ServiceRow] {
        serviceRows.filter { !$0.record.state.isTerminal }
    }

    /// Actually up, as opposed to merely on the books. An expired lease still has
    /// a row; it does not have a running process.
    var runningServices: [ServiceRow] {
        serviceRows.filter(\.record.state.isRunning)
    }

    private(set) var agentSummaries: [AgentSummary] = []
    private(set) var agentProfiles: [AgentProfile] = []
    private(set) var recentMessages: [AgentMessage] = []
    private(set) var externalServices: [ExternalService] = []
    private(set) var sessions: [AgentSession] = []

    var awaitingReplies: [AgentMessage] { recentMessages.filter(\.isAwaitingReply) }
    var awaitingReplyCount: Int { awaitingReplies.count }

    var criticalCount: Int { attention.filter { $0.severity == .critical }.count }
    var warningCount: Int { attention.filter { $0.severity == .warning }.count }


    // MARK: - Menu-bar summary
    //
    // One item, because the app puts up one — see `MenuBarItemController`, whose
    // own comment records the collapse from five to two to one.
    //
    // This block used to open by explaining "two items, two deliberately
    // different silhouettes", and to carry a full second set of properties —
    // `connectionsGlyph`, `connectionsText`, `connectionsTint`,
    // `connectionsTooltip` — computing a live summary of the network for an item
    // that no longer existed. Nothing read them. They were the same drift the
    // design audit's menu-bar check was added to catch in the *documentation*,
    // one layer down where a script comparing prose against
    // `MenuBarItemController(identifier:)` could not see them: every fact they
    // assembled is on the Connections tab of the popover, which is where it is
    // actually read. Deleted rather than kept as a seam — the popover is the
    // seam, and a second item would start from it.

    var fleetGlyph: String { "square.stack.3d.up.fill" }

    /// The one number worth acting on: someone waiting on you, then anything
    /// wrong, then how many services are actually running.
    var fleetText: String {
        let cpu = system.cpu.sampled ? ConsoleFmt.utilPercent(system.cpu.usage) : "—"
        let memory = system.memory.totalBytes > 0
            ? ConsoleFmt.utilPercent(system.memory.usedShare) : "—"
        var text = "CPU \(cpu)  RAM \(memory)"
        if !connected { text += "  Offline" }
        else if awaitingReplyCount > 0 { text += "  !\(awaitingReplyCount)" }
        else if criticalCount + warningCount > 0 { text += "  !\(criticalCount + warningCount)" }
        return text
    }

    var fleetTint: StatusTone? {
        if !connected { return .bad }
        if criticalCount > 0 { return .bad }
        if awaitingReplyCount > 0 || warningCount > 0 { return .warn }
        return nil
    }

    var fleetTooltip: String {
        guard connected, let daemon else { return "FleetConsole — controller not running" }
        var lines: [String] = []
        var counts = ["\(runningServices.count) running"]
        if !unmanaged.isEmpty { counts.append("\(unmanaged.count) unmanaged") }
        if criticalCount > 0 { counts.append("\(criticalCount) critical") }
        if warningCount > 0 { counts.append("\(warningCount) warning") }
        lines.append(counts.joined(separator: " · "))

        for profile in agentProfiles.prefix(4) {
            var line = "\(profile.id): \(profile.headline)"
            if profile.awaitingReply > 0 {
                line += " — \(profile.awaitingReply) awaiting your answer"
            }
            lines.append(line)
        }
        if let soonest = agentProfiles.compactMap(\.nextLeaseExpiry).min() {
            lines.append("next lease expires \(Fmt.relative(soonest))")
        }
        // One line of network, and only when something is wrong with it.
        //
        // The collapse to a single menu-bar item took the network summary off the
        // menu bar with the Connections item, and nothing replaced it: with the
        // link down or the tailnet stopped, the one always-visible surface said
        // "3 running" and explained none of the health checks that were about to
        // start failing. This is not the second item coming back — it makes no
        // claim in the glyph and never changes `fleetTint`, because a dropped
        // Wi-Fi is not a fact about the fleet. It is the sentence that saves you
        // opening the popover to find out why.
        if let fault = networkFault { lines.append(fault) }
        lines.append("fleetd up \(Fmt.duration(daemon.uptime))")
        return lines.joined(separator: "\n")
    }

    /// The network in one line, or nil when there is nothing to say.
    ///
    /// Only the conditions that break something: no route off the machine, and a
    /// tailnet that is installed but not running — which silently strips every
    /// `100.x` address the device probes depend on. A working network produces no
    /// line at all, on the same rule as the VLAN chrome: absent, not "all fine".
    private var networkFault: String? {
        if network.internet.reachable == false { return "no internet — \(network.internet.summary)" }
        if !network.ethernet.connected && !network.wifi.connected {
            return "no network link — neither Ethernet nor Wi-Fi is connected"
        }
        if network.tailscale.installed && !network.tailscale.running {
            return "Tailscale \(network.tailscale.backendState.lowercased()) — 100.x addresses will not resolve"
        }
        let unreachable = deviceRows.filter { $0.record.health == .unreachable }
        if !unreachable.isEmpty {
            return "\(unreachable.count) device(s) unreachable: "
                + unreachable.map(\.record.name).joined(separator: ", ")
        }
        return nil
    }

    /// Evidence older than this is rendered as "unknown (stale)" rather than as its
    /// last-known-good value.
    var staleTolerance: TimeInterval {
        (daemon?.tickIntervalSec ?? 5) * 3
    }

    func service(id: String) -> ServiceRecord? {
        serviceRows.first { $0.id == id }?.record
    }

    // MARK: - Actions

    /// `surfacesErrors` is the difference between a verb and a poll.
    ///
    /// A failed **action** — stop, restart, kill — has to interrupt: you asked
    /// for something, it did not happen, and you need to know before you assume
    /// it did. A failed **refresh** must not. `refreshAll()` runs on every
    /// popover open, so routing its failure to `actionError` meant that with the
    /// controller down, clicking the menu-bar item raised a modal alert saying
    /// the socket was missing — every single time, on top of the
    /// `ControllerDownBanner` and the footer pip that were already saying the
    /// same thing in the same window. Three copies of one fact, one of them
    /// blocking, for a condition the user did not cause and cannot dismiss by
    /// acknowledging it.
    ///
    /// A refresh failure is ambient state, and the app already has a place for
    /// ambient state: `connected` / `connectionError`, which the banner reads.
    private func perform(_ request: RPCRequest, serviceID: String?, timeout: TimeInterval = 30,
                         surfacesErrors: Bool = true,
                         then: (() -> Void)? = nil) {
        if let serviceID { busyServiceIDs.insert(serviceID) }
        DaemonClient.shared.send(request, timeout: timeout) { [weak self] result in
            guard let self else { return }
            if let serviceID { self.busyServiceIDs.remove(serviceID) }
            // `then` runs on both paths deliberately. It is a *finally*, not a
            // success handler: its callers use it to clear an in-flight flag,
            // and a flag cleared only on success leaves a control spinning for
            // ever the one time the controller does not answer — which is
            // precisely when you are looking at it.
            defer { then?() }
            switch result {
            case .success(let response):
                if let snapshot = response.snapshot { self.apply(snapshot) }
            case .failure(let error):
                if surfacesErrors {
                    self.actionError = error.localizedDescription
                } else {
                    self.connected = false
                    self.lastSnapshotReceivedUptime = nil
                    self.connectionError = error.localizedDescription
                }
            }
        }
    }

    func stop(_ record: ServiceRecord) {
        perform(RPCRequest(op: .stop, serviceID: record.id, reason: "stopped from FleetConsole"),
                serviceID: record.id)
    }

    func restart(_ record: ServiceRecord) {
        perform(RPCRequest(op: .restart, serviceID: record.id, reason: "restarted from FleetConsole"),
                serviceID: record.id, timeout: 90)
    }

    func renew(_ record: ServiceRecord, ttl: TimeInterval? = nil) {
        perform(RPCRequest(op: .renew, serviceID: record.id, ttlSec: ttl), serviceID: record.id)
    }

    /// Adopts an unmanaged process into the registry.
    ///
    /// The third answer on an unmanaged row, between "this is expected, stop
    /// telling me" (allow-list) and "I will go look at it myself" (Activity
    /// Monitor): *this one matters, watch it*. It gets an owner, a purpose, a
    /// lease and a timeline, and the controller still refuses to signal it — so
    /// unlike End Process this is not a destructive verb and needs no feature
    /// flag, no uid check and no confirmation.
    func claim(_ process: UnmanagedProcess) {
        claim(unmanagedID: process.id, name: process.command)
    }

    /// The same verb from the process table, where a row is a pid rather than an
    /// entry in the reconciler's list. The controller accepts a bare pid and
    /// re-verifies it either way, so this is the same call with a weaker
    /// identifier — not a second, looser path in.
    func claim(pid: Int32, name: String) {
        claim(unmanagedID: String(pid), name: name)
    }

    private func claim(unmanagedID: String, name: String) {
        perform(RPCRequest(op: .claim,
                           unmanagedID: unmanagedID,
                           friendlyName: name,
                           purpose: "claimed from the unmanaged list",
                           agent: "operator"),
                serviceID: nil)
    }

    /// Adds a command to the expected-listener allow-list in config.json. This is
    /// the explicit, reviewable act the threat model asks for — one click, but it
    /// leaves a config entry and an event behind, not a hidden dismissal.
    func markExpected(_ command: String) {
        perform(RPCRequest(op: .ignoreCommand, command: command), serviceID: nil)
    }

    func pruneHistory(olderThan: TimeInterval = 3600) {
        perform(RPCRequest(op: .prune, ttlSec: olderThan), serviceID: nil)
    }

    func pause(_ record: ServiceRecord) {
        perform(RPCRequest(op: .pause, serviceID: record.id), serviceID: record.id)
    }

    func resume(_ record: ServiceRecord) {
        perform(RPCRequest(op: .resume, serviceID: record.id), serviceID: record.id)
    }

    func forceKill(_ record: ServiceRecord) {
        perform(RPCRequest(op: .kill, serviceID: record.id, reason: "force killed from FleetConsole"),
                serviceID: record.id)
    }

    func reply(to message: AgentMessage, with text: String) {
        perform(RPCRequest(op: .reply, body: text, messageID: message.id), serviceID: nil)
    }

    func markMessagesSeen() {
        guard DaemonClient.shared.requestPolicy.allows(.markSeen) else { return }
        guard recentMessages.contains(where: { $0.seenAt == nil }) else { return }
        perform(RPCRequest(op: .markSeen), serviceID: nil, surfacesErrors: false)
    }

    /// True while a re-evidence request is in flight, so the control that
    /// started it can say so. A refresh that completes in 200 ms and changes
    /// nothing visible is indistinguishable from a button that does nothing —
    /// which is exactly what the old one was.
    var isReconciling = false

    func reconcileNow() {
        guard !isReconciling else { return }
        isReconciling = true
        perform(RPCRequest(op: .reconcile), serviceID: nil) { [weak self] in
            self?.isReconciling = false
        }
    }

    /// The refresh a *person* asked for: re-probe everything this app samples
    /// itself, and make the controller re-capture the process table and re-run
    /// the sweep.
    ///
    /// Distinct from `refreshAll()`, and the distinction is the bug this fixes.
    /// `refreshAll` sends `.snapshot`, which the controller answers out of
    /// memory without sampling anything — correct for the automatic call on
    /// every popover open, and worthless as a button, because the subscription
    /// already pushes that same state every supervisor tick. Services, unmanaged
    /// processes and agent sessions are only rebuilt inside `runReconcile`, so
    /// `.reconcile` is the only request that can change what the Services and
    /// Agents tabs are showing.
    func reEvidence() {
        network.refresh()
        system.sample()
        processes.sample()
        refreshDevices()
        reconcileNow()
    }

    func refreshDevices() {
        guard DaemonClient.shared.requestPolicy.allows(.refreshDevices) else { return }
        perform(RPCRequest(op: .refreshDevices), serviceID: nil, surfacesErrors: false)
    }

    func refreshAll() {
        network.refresh()
        system.sample()
        refreshDevices()
        // A poll, not a verb — see `perform`. The banner reports a down
        // controller; a modal must not.
        perform(RPCRequest(op: .snapshot), serviceID: nil, surfacesErrors: false)
    }

    func loadEvents(serviceID: String?, limit: Int = 300, completion: @escaping ([ServiceEvent]) -> Void) {
        DaemonClient.shared.send(RPCRequest(op: .events, serviceID: serviceID, limit: limit)) { result in
            switch result {
            case .success(let response): completion(response.events ?? [])
            case .failure: completion([])
            }
        }
    }

    func loadLogs(serviceID: String, stream: String, completion: @escaping (LogChunk?) -> Void) {
        DaemonClient.shared.send(RPCRequest(op: .logs, serviceID: serviceID, stream: stream,
                                            maxBytes: 120_000)) { result in
            switch result {
            case .success(let response): completion(response.logs)
            case .failure: completion(nil)
            }
        }
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    func openConfigFile() {
        NSWorkspace.shared.open(FleetPaths.config)
    }
}
