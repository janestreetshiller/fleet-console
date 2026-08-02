import Foundation

// One consistent view of everything, and what the client derives from it. The
// daemon pushes a `Snapshot` on every state change and the UI never polls, so this
// is the whole contract between them. `AttentionItem` is derived client-side, so
// the CLI and the app cannot disagree about what needs looking at.
// MARK: - Attention

public enum AttentionSeverity: String, Codable, Sendable {
    case critical, warning
}

public struct AttentionItem: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var severity: AttentionSeverity
    public var title: String
    public var detail: String
    public var serviceID: String?
    public var unmanagedID: String?
    public var since: Date

    public init(id: String, severity: AttentionSeverity, title: String, detail: String,
                serviceID: String? = nil, unmanagedID: String? = nil, since: Date = Date()) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.serviceID = serviceID
        self.unmanagedID = unmanagedID
        self.since = since
    }
}

// MARK: - Snapshot

public struct DaemonInfo: Codable, Sendable, Hashable {
    public var version: String
    public var pid: Int32
    public var startedAt: Date
    public var lastTickAt: Date?
    public var lastReconcileAt: Date?
    public var tickIntervalSec: Double
    public var socketPath: String

    public init(version: String, pid: Int32, startedAt: Date, lastTickAt: Date? = nil,
                lastReconcileAt: Date? = nil, tickIntervalSec: Double = 5, socketPath: String = "") {
        self.version = version
        self.pid = pid
        self.startedAt = startedAt
        self.lastTickAt = lastTickAt
        self.lastReconcileAt = lastReconcileAt
        self.tickIntervalSec = tickIntervalSec
        self.socketPath = socketPath
    }

    public var uptime: TimeInterval { Date().timeIntervalSince(startedAt) }
}

public struct Snapshot: Codable, Sendable {
    public var generatedAt: Date
    public var daemon: DaemonInfo
    public var services: [ServiceRecord]
    public var unmanaged: [UnmanagedProcess]
    public var devices: [DeviceRecord]
    public var attention: [AttentionItem]
    public var recentEvents: [ServiceEvent]
    public var messages: [AgentMessage] = []
    public var external: [ExternalService] = []
    public var sessions: [AgentSession] = []

    public init(generatedAt: Date = Date(), daemon: DaemonInfo, services: [ServiceRecord] = [],
                unmanaged: [UnmanagedProcess] = [], devices: [DeviceRecord] = [],
                attention: [AttentionItem] = [], recentEvents: [ServiceEvent] = [],
                messages: [AgentMessage] = [], external: [ExternalService] = [],
                sessions: [AgentSession] = []) {
        self.messages = messages
        self.external = external
        self.sessions = sessions
        self.generatedAt = generatedAt
        self.daemon = daemon
        self.services = services
        self.unmanaged = unmanaged
        self.devices = devices
        self.attention = attention
        self.recentEvents = recentEvents
    }

    /// On the books: everything not finished, including an expired lease that is
    /// being reported rather than reaped. This is what a list shows.
    public var activeServices: [ServiceRecord] { services.filter { !$0.state.isTerminal } }

    /// Actually up. This is what a count worded "running" shows.
    public var runningServices: [ServiceRecord] { services.filter(\.state.isRunning) }
}

extension Snapshot {
    /// Derived on the client so both the CLI and the app show the same thing
    /// without adding another server round trip.
    public var agentSummaries: [AgentSummary] {
        let live = services.filter { !$0.state.isTerminal }
        let byAgent = Dictionary(grouping: live, by: \.ownerAgent)
        let messagesByAgent = Dictionary(grouping: messages, by: \.agent)
        // An agent with no services but an unanswered question still needs to
        // appear — that is precisely the case you must not miss.
        let names = Set(byAgent.keys).union(messagesByAgent.keys)

        return names.map { agent in
            let records = byAgent[agent] ?? []
            let mail = messagesByAgent[agent] ?? []
            var summary = AgentSummary(
                id: agent,
                // `records` is everything not finished, which is right for ports and
                // for attention: an expired record still holds its ports. It is
                // wrong for a number labelled "running" — see ServiceState.isRunning.
                running: records.filter(\.state.isRunning).count,
                needingAttention: records.filter { $0.state.needsAttention }.count,
                ports: Array(Set(records.flatMap(\.effectivePorts))).sorted(),
                oldestStart: records.map(\.startedAt).min(),
                nextLeaseExpiry: records.map(\.leaseExpiresAt).min(),
                totalCPU: records.compactMap { $0.resources.cpuPct }.reduce(0, +),
                totalMemMB: records.compactMap { $0.resources.memMB }.reduce(0, +),
                purposes: Array(Set(records.map(\.purpose))).sorted())
            summary.awaitingReply = mail.filter(\.isAwaitingReply).count
            summary.lastMessageAt = mail.map(\.createdAt).max()
            return summary
        }
        .sorted {
            ($0.awaitingReply, $0.needingAttention, $0.running)
                > ($1.awaitingReply, $1.needingAttention, $1.running)
        }
    }

    public var awaitingReplyCount: Int { messages.filter(\.isAwaitingReply).count }

    /// The full picture for one agent, including everything it has *done* — not
    /// just what it happens to be running this second. An idle agent still has a
    /// history worth showing; "0 services" on its own says nothing.
    public var agentProfiles: [AgentProfile] {
        let byAgent = Dictionary(grouping: services, by: \.ownerAgent)
        let messagesByAgent = Dictionary(grouping: messages, by: \.agent)
        let names = Set(byAgent.keys).union(messagesByAgent.keys)

        return names.map { name in
            let all = byAgent[name] ?? []
            let live = all.filter { !$0.state.isTerminal }
            let mail = (messagesByAgent[name] ?? []).sorted { $0.createdAt > $1.createdAt }

            var profile = AgentProfile(id: name)
            profile.running = live.filter(\.state.isRunning).count
            profile.paused = live.filter { $0.state == .paused }.count
            profile.needingAttention = live.filter { $0.state.needsAttention }.count
            profile.ports = Array(Set(live.flatMap(\.effectivePorts))).sorted()
            profile.cpuPct = live.compactMap { $0.resources.cpuPct }.reduce(0, +)
            profile.memMB = live.compactMap { $0.resources.memMB }.reduce(0, +)
            profile.nextLeaseExpiry = live.map(\.leaseExpiresAt).min()

            profile.totalLaunched = all.count
            profile.totalStopped = all.filter { $0.state == .stopped }.count
            profile.totalCrashed = all.filter { $0.state == .crashed }.count
            profile.totalLeaked = all.filter(\.reapedForExpiry).count
            profile.totalRestarts = all.reduce(0) { $0 + $1.restartCount }
            profile.healthFailures = all.reduce(0) { $0 + $1.healthFailureCount }
            profile.totalRuntime = all.reduce(0) { total, record in
                total + (record.state.isTerminal
                         ? record.updatedAt.timeIntervalSince(record.startedAt)
                         : Date().timeIntervalSince(record.startedAt))
            }

            profile.firstSeen = all.map(\.startedAt).min()
            profile.lastActivityAt = [all.map(\.updatedAt).max(), mail.first?.createdAt]
                .compactMap { $0 }.max()
            profile.projects = Array(Set(all.map(\.cwd))).sorted()
            profile.purposes = Array(Set(live.map(\.purpose))).sorted()
            profile.recentServices = all.sorted { $0.startedAt > $1.startedAt }.prefix(5).map { $0 }

            profile.messageCount = mail.count
            profile.awaitingReply = mail.filter(\.isAwaitingReply).count
            profile.lastMessage = mail.first
            return profile
        }
        .sorted {
            ($0.awaitingReply, $0.needingAttention, $0.running, $0.totalLaunched)
                > ($1.awaitingReply, $1.needingAttention, $1.running, $1.totalLaunched)
        }
    }
}
