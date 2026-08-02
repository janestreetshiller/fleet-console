import Foundation

// The machine and the network around it: host metrics, local tools the app can
// see, and the other devices on the tailnet.
// MARK: - Host metrics

public struct HostMetrics: Codable, Sendable, Hashable {
    public var cpuPct: Double?
    public var memUsedGB: Double?
    public var memTotalGB: Double?
    public var diskUsedGB: Double?
    public var diskTotalGB: Double?
    public var gpuPct: Double?
    public var collectedAt: Date?

    public init(cpuPct: Double? = nil, memUsedGB: Double? = nil, memTotalGB: Double? = nil,
                diskUsedGB: Double? = nil, diskTotalGB: Double? = nil, gpuPct: Double? = nil,
                collectedAt: Date? = nil) {
        self.cpuPct = cpuPct
        self.memUsedGB = memUsedGB
        self.memTotalGB = memTotalGB
        self.diskUsedGB = diskUsedGB
        self.diskTotalGB = diskTotalGB
        self.gpuPct = gpuPct
        self.collectedAt = collectedAt
    }

    public var hasAny: Bool {
        cpuPct != nil || memUsedGB != nil || diskUsedGB != nil
    }

    public var line: String {
        var parts: [String] = []
        if let cpuPct { parts.append(String(format: "CPU %.0f%%", cpuPct)) }
        if let memUsedGB, let memTotalGB {
            parts.append(String(format: "RAM %.1f/%.0f GB", memUsedGB, memTotalGB))
        }
        if let diskUsedGB, let diskTotalGB {
            parts.append(String(format: "SSD %.0f/%.0f GB", diskUsedGB, diskTotalGB))
        }
        if let gpuPct { parts.append(String(format: "GPU %.0f%%", gpuPct)) }
        return parts.isEmpty ? "no metrics" : parts.joined(separator: " · ")
    }
}

// MARK: - Local tools
//
// Long-lived tools you run yourself — a dashboard, an inference server, a driver.
// They are not launched through the controller and never will be, but they are
// not "unmanaged" in the sense of a leak either: you meant them to be there.
// Declaring them turns anonymous noise into an inventory, and it means their own
// menu-bar apps have nothing left to tell you.

public struct ExternalService: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var symbol: String
    public var running: Bool
    public var pid: Int32?
    public var ports: [Int]
    public var declaredPorts: [Int]
    public var commandLine: String?
    /// Opened when you click the row, if it has a UI.
    public var url: String?
    public var startedAt: Date?
    public var checkedAt: Date

    public init(id: String, name: String, symbol: String = "wrench.and.screwdriver",
                running: Bool = false, pid: Int32? = nil, ports: [Int] = [],
                declaredPorts: [Int] = [], commandLine: String? = nil, url: String? = nil,
                startedAt: Date? = nil, checkedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.running = running
        self.pid = pid
        self.ports = ports
        self.declaredPorts = declaredPorts
        self.commandLine = commandLine
        self.url = url
        self.startedAt = startedAt
        self.checkedAt = checkedAt
    }

    public var summary: String {
        guard running else { return "not running" }
        var parts: [String] = []
        if !ports.isEmpty { parts.append(Fmt.ports(ports)) }
        if let pid { parts.append("pid \(pid)") }
        if let startedAt { parts.append("up \(Fmt.duration(Date().timeIntervalSince(startedAt)))") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Devices

public struct DeviceEvidence: Codable, Sendable, Hashable {
    public var icmpOK: Bool?
    public var icmpRTTms: Double?
    public var tcpOK: Bool?
    public var tcpPort: Int?
    public var tailscaleOnline: Bool?
    public var tailscaleLastSeen: Date?
    public var checkedAt: Date?
    public var isSelf: Bool

    public init(icmpOK: Bool? = nil, icmpRTTms: Double? = nil, tcpOK: Bool? = nil,
                tcpPort: Int? = nil, tailscaleOnline: Bool? = nil, tailscaleLastSeen: Date? = nil,
                checkedAt: Date? = nil, isSelf: Bool = false) {
        self.icmpOK = icmpOK
        self.icmpRTTms = icmpRTTms
        self.tcpOK = tcpOK
        self.tcpPort = tcpPort
        self.tailscaleOnline = tailscaleOnline
        self.tailscaleLastSeen = tailscaleLastSeen
        self.checkedAt = checkedAt
        self.isSelf = isSelf
    }

    /// Reachability is only claimed when a probe actually succeeded.
    public var reachable: Bool? {
        if icmpOK == true || tcpOK == true { return true }
        if icmpOK == nil && tcpOK == nil { return nil }
        if icmpOK == false && tcpOK == false { return false }
        return nil
    }
}

public enum DeviceHealth: String, Codable, Sendable {
    case reachable      // a probe succeeded
    case partial        // some probes succeeded, others failed
    case unreachable    // probes ran and all failed
    case unknown        // no probe has completed yet

    public var label: String {
        switch self {
        case .reachable: return "Reachable"
        case .partial: return "Partially reachable"
        case .unreachable: return "Unreachable"
        case .unknown: return "Unknown"
        }
    }
}

public struct DeviceRecord: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var model: String
    /// LAN hostname or IP, optional.
    public var localHost: String?
    /// Tailscale DNS name or magic-DNS short name.
    public var tailscaleHost: String?
    public var tailscaleIP: String?
    public var localIP: String?
    /// TCP port used as a reachability probe (e.g. 22).
    public var probePort: Int?
    public var evidence: DeviceEvidence
    public var lastReachableAt: Date?
    /// Services managed by *that* machine's controller, fetched read-only over SSH.
    /// FleetConsole never controls a remote process — it only reports one.
    public var remoteServices: [ServiceRecord] = []
    public var remoteError: String?
    public var remoteCheckedAt: Date?
    /// CPU / RAM / SSD for this machine — what the AI-Pocket badge used to show.
    public var metrics: HostMetrics = HostMetrics()

    public init(id: String, name: String, model: String = "", localHost: String? = nil,
                tailscaleHost: String? = nil, tailscaleIP: String? = nil, localIP: String? = nil,
                probePort: Int? = 22, evidence: DeviceEvidence = DeviceEvidence(),
                lastReachableAt: Date? = nil) {
        self.id = id
        self.name = name
        self.model = model
        self.localHost = localHost
        self.tailscaleHost = tailscaleHost
        self.tailscaleIP = tailscaleIP
        self.localIP = localIP
        self.probePort = probePort
        self.evidence = evidence
        self.lastReachableAt = lastReachableAt
    }

    public var health: DeviceHealth {
        if evidence.isSelf { return .reachable }
        let e = evidence
        let results = [e.icmpOK, e.tcpOK, e.tailscaleOnline].compactMap { $0 }
        if results.isEmpty { return .unknown }
        if results.allSatisfy({ $0 }) { return .reachable }
        if results.contains(true) { return .partial }
        return .unreachable
    }
}
