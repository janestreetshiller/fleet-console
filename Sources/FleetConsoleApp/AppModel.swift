import Foundation
import SwiftUI
import FleetCore

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
    private(set) var lastSnapshotReceivedUptime: TimeInterval?
    var actionError: String?
    var busyServiceIDs: Set<String> = []

    let settings = Settings()

    let network: NetworkMonitor
    let actions = NetworkActions()
    let license = LicenseManager()
    let ourosBilling: OurosBilling
    let system: SystemMonitor
    let storage = StorageScanner()
    let breakdown = StorageBreakdown()
    let processes: ProcessInventory
    let hosts = HostProbe()
    let agentCost = AgentCostProbe()

    var clockTick: Int = 0

    var requestedSection: FleetSection?

    @ObservationIgnored nonisolated(unsafe) private var clockTimer: Timer?
    private var didInitialLoad = false

    init(billing: OurosBilling? = nil, connectToController: Bool = true) {
        ourosBilling = billing ?? OurosBilling()
        let intervals = settings.intervals
        network = NetworkMonitor(interval: intervals.clampedNetworkRefresh)
        system = SystemMonitor { [license] feature in license.isUnlocked(feature) }
        processes = ProcessInventory(interval: intervals.clampedProcessSample)

        if connectToController {
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
        }
        network.refresh()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.clockTick &+= 1
                self?.expireTopologyEvidence()
            }
        }
    }

    deinit {
        clockTimer?.invalidate()
    }

    func apply(_ snapshot: Snapshot) {
        connected = true
        connectionError = nil
        topologySource = snapshot
        topology = FleetTopology(snapshot: snapshot)
        daemon = snapshot.daemon
        lastSnapshotAt = snapshot.generatedAt
        lastSnapshotReceivedUptime = ProcessInfo.processInfo.systemUptime

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
        if mailbox != snapshot.messages {
            let previouslyKnown = Set(mailbox.map(\.id))
            mailbox = snapshot.messages
            recentMessages = mailbox.filter { !dismissals.contains($0.id) }
            let fresh = recentMessages.filter { !previouslyKnown.contains($0.id) && $0.seenAt == nil }
            if !didInitialLoad {
                didInitialLoad = true
            } else {
                for message in fresh { Notifier.post(message) }
            }
        }
        if externalServices != snapshot.external { externalServices = snapshot.external }
        if sessions != snapshot.sessions { sessions = snapshot.sessions }
        if jobObservations.last.map({ snapshot.generatedAt.timeIntervalSince($0.time) >= 4 }) ?? true {
            let agentEntries = snapshot.sessions.prefix(32).map {
                "Detected " + InvestigationRequest.label($0.tool) + " · pid \($0.pid)"
            }
            let serviceEntries = snapshot.services.prefix(32).map {
                "Service " + InvestigationRequest.label($0.id) + " · owner " + InvestigationRequest.label($0.ownerAgent)
                    + " · pid " + ($0.pid.map(String.init) ?? "none") + " · " + $0.state.rawValue
            }
            jobObservations.append(JobObservation(time: snapshot.generatedAt, entries: agentEntries + serviceEntries))
            if jobObservations.count > 120 { jobObservations.removeFirst(jobObservations.count - 120) }
        }
        if unmanaged != snapshot.unmanaged { unmanaged = snapshot.unmanaged }
        if attention != snapshot.attention { attention = snapshot.attention }
        if recentEvents != snapshot.recentEvents { recentEvents = snapshot.recentEvents }

        if settings.features.showAgentSpend { agentCost.refresh() }
    }

    var activeServices: [ServiceRow] {
        serviceRows.filter { !$0.record.state.isTerminal }
    }

    var runningServices: [ServiceRow] {
        serviceRows.filter(\.record.state.isRunning)
    }

    private(set) var agentSummaries: [AgentSummary] = []
    private(set) var agentProfiles: [AgentProfile] = []
    private(set) var recentMessages: [AgentMessage] = []
    @ObservationIgnored private var mailbox: [AgentMessage] = []
    @ObservationIgnored private let dismissals = MessageDismissals()
    private(set) var externalServices: [ExternalService] = []
    struct JobObservation: Identifiable {
        let time: Date
        let entries: [String]
        var id: Date { time }
    }
    private(set) var jobObservations: [JobObservation] = []
    @ObservationIgnored private var topologySource: Snapshot?
    private(set) var topology: FleetTopology?

    private func expireTopologyEvidence() {
        guard let deadline = topology?.validUntil, Date() > deadline, let source = topologySource else { return }
        topology = FleetTopology(snapshot: source)
    }
    private(set) var sessions: [AgentSession] = []

    var awaitingReplies: [AgentMessage] { recentMessages.filter(\.isAwaitingReply) }
    var awaitingReplyCount: Int { awaitingReplies.count }

    var criticalCount: Int { attention.filter { $0.severity == .critical }.count }
    var warningCount: Int { attention.filter { $0.severity == .warning }.count }

    var fleetMeters: [MenuBarMeter] {
        [MenuBarMeter(label: "CPU",
                      value: system.cpu.sampled ? ConsoleFmt.utilPercent(system.cpu.usage) : "—"),
         MenuBarMeter(label: "RAM",
                      value: system.memory.totalBytes > 0 ? ConsoleFmt.utilPercent(system.memory.usedShare) : "—"),
         MenuBarMeter(label: "DISK",
                      value: system.storage.totalBytes > 0 ? ConsoleFmt.utilPercent(system.storage.usedShare) : "—")]
    }

    var fleetAlert: String {
        if !connected { return "Offline" }
        if awaitingReplyCount > 0 { return "!\(awaitingReplyCount)" }
        if criticalCount + warningCount > 0 { return "!\(criticalCount + warningCount)" }
        return ""
    }

    var fleetStatusLine: String {
        guard connected else { return "Controller offline" }
        if awaitingReplyCount > 0 { return "\(awaitingReplyCount) awaiting your answer" }
        if criticalCount > 0 { return "\(criticalCount) critical · \(warningCount) warning" }
        if warningCount > 0 { return "\(warningCount) warning" }
        return "\(runningServices.count) services running"
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
        if let fault = networkFault { lines.append(fault) }
        lines.append("fleetd up \(Fmt.duration(daemon.uptime))")
        return lines.joined(separator: "\n")
    }

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

    var staleTolerance: TimeInterval {
        (daemon?.tickIntervalSec ?? 5) * 3
    }

    func service(id: String) -> ServiceRecord? {
        serviceRows.first { $0.id == id }?.record
    }

    private func perform(_ request: RPCRequest, serviceID: String?, timeout: TimeInterval = 30,
                         surfacesErrors: Bool = true,
                         then: (() -> Void)? = nil) {
        if let serviceID { busyServiceIDs.insert(serviceID) }
        DaemonClient.shared.send(request, timeout: timeout) { [weak self] result in
            guard let self else { return }
            if let serviceID { self.busyServiceIDs.remove(serviceID) }
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

    func claim(_ process: UnmanagedProcess) {
        claim(unmanagedID: process.id, name: process.command)
    }

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

    func dismissMessages(_ ids: [Int64]) {
        guard !ids.isEmpty else { return }
        dismissals.insert(ids)
        recentMessages = mailbox.filter { !dismissals.contains($0.id) }
    }

    func markMessagesSeen() {
        guard DaemonClient.shared.requestPolicy.allows(.markSeen) else { return }
        guard recentMessages.contains(where: { $0.seenAt == nil }) else { return }
        perform(RPCRequest(op: .markSeen), serviceID: nil, surfacesErrors: false)
    }

    var isReconciling = false

    func reconcileNow() {
        guard !isReconciling else { return }
        isReconciling = true
        perform(RPCRequest(op: .reconcile), serviceID: nil) { [weak self] in
            self?.isReconciling = false
        }
    }

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

final class MessageDismissals {
    private static let key = "fleetconsole.dismissedMessages"
    private static let limit = 2_000
    private let defaults: UserDefaults
    private var ids: Set<Int64>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ids = Set((defaults.array(forKey: Self.key) as? [NSNumber] ?? []).map(\.int64Value))
    }

    func contains(_ id: Int64) -> Bool { ids.contains(id) }

    func insert(_ new: [Int64]) {
        ids.formUnion(new)
        if ids.count > Self.limit { ids = Set(ids.sorted().suffix(Self.limit)) }
        defaults.set(ids.sorted().map(NSNumber.init(value:)), forKey: Self.key)
    }
}
