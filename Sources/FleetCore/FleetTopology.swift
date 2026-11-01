import Foundation

/// A projection of controller evidence, shared by the desktop and CLI. Edges
/// express recorded ownership or observations, never inferred dependencies.
public struct FleetTopology: Codable, Sendable, Equatable {
    public struct Node: Codable, Sendable, Identifiable, Equatable {
        public enum Kind: String, Codable, Sendable { case owner, service, process, listener, session }
        public var id: String
        public var kind: Kind
        public var title: String
        public var detail: String
        public var serviceID: String?
        public var owner: String?
        public var observedAt: Date?
        public var cpuPct: Double?
        public var memMB: Double?
    }
    public struct Edge: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable { case owns, verifiedLeader, observedListener }
        public var source: String
        public var target: String
        public var kind: Kind
        public var observedAt: Date?
        public var provenance: String
    }
    public var schemaVersion = 1
    public var generatedAt: Date
    public var isStale: Bool
    /// Next evidence expiry; clients can update once at this boundary.
    public var validUntil: Date?
    public var nodes: [Node]
    public var edges: [Edge]
    public var limitations: [String]

    public init(snapshot: Snapshot, owner: String? = nil, now: Date = Date()) {
        generatedAt = snapshot.generatedAt
        let interval = snapshot.daemon.tickIntervalSec
        let tolerance = interval.isFinite && interval > 0 ? max(1, interval * 3) : 15
        isStale = now.timeIntervalSince(snapshot.generatedAt) > tolerance
        validUntil = nil
        nodes = []; edges = []
        limitations = [
            "Ownership is a registry record; it does not identify a detected agent session.",
            "Listeners show observed group ports, not connections or dependencies.",
            "Agent reasoning, token velocity, context usage and Ouros account usage are unavailable in the controller snapshot."
        ]
        let services = snapshot.activeServices.filter { owner == nil || $0.ownerAgent == owner }
            .sorted { ($0.ownerAgent, $0.id) < ($1.ownerAgent, $1.id) }
        let mail = snapshot.messages.filter { owner == nil || $0.agent == owner }
        let names = Set(services.map(\.ownerAgent)).union(mail.map(\.agent)).sorted()
        let waitingByOwner = Dictionary(grouping: mail.filter(\.isAwaitingReply), by: \.agent)
        for name in names {
            let waiting = waitingByOwner[name]?.count ?? 0
            nodes.append(Node(id: "owner:" + name, kind: .owner, title: name,
                              detail: "\(waiting) awaiting replies", owner: name))
        }
        var expiryDates = [snapshot.generatedAt.addingTimeInterval(tolerance)]
        for service in services {
            expiryDates += [service.evidence.checkedAt, service.resources.sampledAt].compactMap { $0?.addingTimeInterval(tolerance) }
            let id = "service:" + service.id
            let evidenceFresh = !isStale && !service.evidence.isStale(now: now, tolerance: tolerance)
            let sampleFresh = !isStale && service.resources.sampledAt.map { now.timeIntervalSince($0) <= tolerance } == true
            let cpu = sampleFresh ? service.resources.cpuPct.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } : nil
            let mem = sampleFresh ? service.resources.memMB.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } : nil
            let health: String
            if !evidenceFresh { health = "health unavailable or stale" }
            else if service.health.kind == .none { health = "no health check configured" }
            else if !service.evidence.healthCheckRan { health = "health check unavailable" }
            else if let passed = service.evidence.healthPassed { health = passed ? "health check passed" : "health check failed" }
            else { health = "health check unavailable" }
            let ports = service.evidence.portScanRan && evidenceFresh
                ? (service.evidence.listeningPorts.isEmpty ? "no listeners observed" : "listeners observed")
                : "listener scan unavailable or stale"
            let declared = service.declaredPorts.isEmpty ? "" : " · declared \(Fmt.ports(service.declaredPorts))"
            nodes.append(Node(id: id, kind: .service, title: service.friendlyName,
                              detail: "\(service.state.rawValue) · \(service.claimed ? "claimed · visibility only" : "controller launched") · \(health) · \(ports)\(declared)",
                              serviceID: service.id, owner: service.ownerAgent,
                              observedAt: service.evidence.checkedAt, cpuPct: cpu, memMB: mem))
            edges.append(Edge(source: "owner:" + service.ownerAgent, target: id, kind: .owns, observedAt: service.updatedAt, provenance: "fleetd service registry"))
            if evidenceFresh, service.evidence.processExists == true, let pid = service.pid, pid == service.pgid {
                let processID = id + ":leader"
                nodes.append(Node(id: processID, kind: .process, title: "PID \(pid)",
                                  detail: "Identity verified · recorded group \(service.pgid.map(String.init) ?? "unavailable")",
                                  serviceID: service.id, owner: service.ownerAgent, observedAt: service.evidence.checkedAt))
                edges.append(Edge(source: id, target: processID, kind: .verifiedLeader, observedAt: service.evidence.checkedAt, provenance: "fleetd process identity check"))
            }
            if evidenceFresh, service.evidence.portScanRan {
                for port in Set(service.evidence.listeningPorts).sorted() where (1...65535).contains(port) {
                    let portID = id + ":port:\(port)"
                    nodes.append(Node(id: portID, kind: .listener, title: ":\(port)", detail: "Observed group listener",
                                      serviceID: service.id, owner: service.ownerAgent, observedAt: service.evidence.checkedAt))
                    edges.append(Edge(source: id, target: portID, kind: .observedListener, observedAt: service.evidence.checkedAt, provenance: "fleetd group listener scan"))
                }
            }
        }
        // Session detection has its own source. Never join tool names, paths or
        // bare PIDs to service owners. Exact owner filtering omits this lane.
        if owner == nil {
            let scannedAt = snapshot.daemon.lastReconcileAt
            let sessionsFresh = !isStale && scannedAt.map { now.timeIntervalSince($0) <= tolerance } == true
            if let scannedAt { expiryDates.append(scannedAt.addingTimeInterval(tolerance)) }
            for session in snapshot.sessions.sorted(by: { $0.id < $1.id }) {
                nodes.append(Node(id: "session:" + session.id, kind: .session, title: session.tool,
                                  detail: "Detected PID \(session.pid) · \(session.projectName) · ownership unlinked" + (sessionsFresh ? "" : " · session scan stale or unavailable"),
                                  observedAt: scannedAt,
                                  cpuPct: !sessionsFresh || !session.cpuPct.isFinite || session.cpuPct < 0 ? nil : session.cpuPct,
                                  memMB: !sessionsFresh || !session.memMB.isFinite || session.memMB < 0 ? nil : session.memMB))
            }
        }
        validUntil = expiryDates.filter { $0 >= now }.min()
    }
}
