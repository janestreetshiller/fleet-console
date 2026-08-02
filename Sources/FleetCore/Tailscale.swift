import Foundation

/// Read-only view of `tailscale status --json`. Never issues control commands —
/// FleetConsole observes the tailnet, it does not reconfigure it.
public struct TailscaleStatus: Sendable {
    public struct Node: Sendable, Hashable {
        public var id: String
        public var hostName: String
        public var dnsName: String
        public var os: String
        public var ips: [String]
        public var online: Bool
        public var isExitNode: Bool
        public var offersExitNode: Bool
        public var lastSeen: Date?
        public var relay: String?
        public var currentAddress: String?
        public var rxBytes: Int64
        public var txBytes: Int64

        /// "metal-mini.tail8a000f.ts.net." → "metal-mini"
        public var shortName: String {
            dnsName.split(separator: ".").first.map(String.init) ?? hostName
        }

        public var ipv4: String? { ips.first { !$0.contains(":") } }
    }

    public var backendState: String
    public var version: String
    public var tailnetName: String?
    public var magicDNSSuffix: String?
    public var selfNode: Node?
    public var peers: [Node]
    public var exitNodeID: String?
    public var capturedAt: Date

    public var isRunning: Bool { backendState == "Running" }

    /// The peer currently being used as this machine's exit node, if any.
    public var activeExitNode: Node? {
        if let peer = peers.first(where: { $0.isExitNode }) { return peer }
        if let id = exitNodeID { return peers.first { $0.id == id } }
        return nil
    }

    public func peer(matching identifier: String) -> Node? {
        let needle = identifier.lowercased()
        return peers.first { node in
            node.shortName.lowercased() == needle
                || node.hostName.lowercased() == needle
                || node.dnsName.lowercased().hasPrefix(needle + ".")
                || node.ips.contains(identifier)
        }
    }

    /// Includes self, so a device configured with this machine's own name resolves.
    public func node(matching identifier: String) -> Node? {
        if let selfNode {
            let needle = identifier.lowercased()
            if selfNode.shortName.lowercased() == needle
                || selfNode.hostName.lowercased() == needle
                || selfNode.dnsName.lowercased().hasPrefix(needle + ".")
                || selfNode.ips.contains(identifier) {
                return selfNode
            }
        }
        return peer(matching: identifier)
    }
}

public enum TailscaleClient {
    public static let candidatePaths = [
        "/usr/local/bin/tailscale",
        "/opt/homebrew/bin/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/System/Volumes/Data/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    ]

    public static var executablePath: String? {
        Shell.which("tailscale", candidates: candidatePaths)
    }

    public enum Outcome: Sendable {
        case notInstalled
        case failed(String)
        case ok(TailscaleStatus)

        public var status: TailscaleStatus? {
            if case .ok(let s) = self { return s }
            return nil
        }
    }

    public static func status(timeout: TimeInterval = 6) -> Outcome {
        guard let path = executablePath else { return .notInstalled }
        let result = Shell.run(path, ["status", "--json"], timeout: timeout)
        guard !result.stdout.isEmpty, let data = result.stdout.data(using: .utf8) else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(message.isEmpty ? "tailscale status returned nothing" : message)
        }
        do {
            return .ok(try parse(data))
        } catch {
            return .failed("could not parse tailscale status: \(error.localizedDescription)")
        }
    }

    static func parse(_ data: Data) throws -> TailscaleStatus {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FleetError.io("unexpected tailscale JSON shape")
        }
        let selfNode = (root["Self"] as? [String: Any]).map(node(from:))
        var peers: [TailscaleStatus.Node] = []
        if let peerMap = root["Peer"] as? [String: [String: Any]] {
            peers = peerMap.values.map(node(from:)).sorted { $0.shortName < $1.shortName }
        }
        var exitNodeID: String?
        if let exit = root["ExitNodeStatus"] as? [String: Any] {
            exitNodeID = exit["ID"] as? String
        }
        var tailnet: String?
        if let current = root["CurrentTailnet"] as? [String: Any] {
            tailnet = current["Name"] as? String
        }
        return TailscaleStatus(backendState: root["BackendState"] as? String ?? "Unknown",
                               version: root["Version"] as? String ?? "",
                               tailnetName: tailnet,
                               magicDNSSuffix: root["MagicDNSSuffix"] as? String,
                               selfNode: selfNode,
                               peers: peers,
                               exitNodeID: exitNodeID,
                               capturedAt: Date())
    }

    private static func node(from dict: [String: Any]) -> TailscaleStatus.Node {
        TailscaleStatus.Node(id: dict["ID"] as? String ?? "",
                             hostName: dict["HostName"] as? String ?? "",
                             dnsName: dict["DNSName"] as? String ?? "",
                             os: dict["OS"] as? String ?? "",
                             ips: dict["TailscaleIPs"] as? [String] ?? [],
                             online: dict["Online"] as? Bool ?? false,
                             isExitNode: dict["ExitNode"] as? Bool ?? false,
                             offersExitNode: dict["ExitNodeOption"] as? Bool ?? false,
                             lastSeen: parseDate(dict["LastSeen"] as? String),
                             relay: (dict["Relay"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                             currentAddress: (dict["CurAddr"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                             rxBytes: (dict["RxBytes"] as? NSNumber)?.int64Value ?? 0,
                             txBytes: (dict["TxBytes"] as? NSNumber)?.int64Value ?? 0)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty, !string.hasPrefix("0001-01-01") else { return nil }
        return isoFractional.date(from: string) ?? iso.date(from: string)
    }
}
