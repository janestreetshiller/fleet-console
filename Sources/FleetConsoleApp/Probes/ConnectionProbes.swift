import Foundation
import FleetCore

// The extra connection surfaces. Each one reports what it actually found —
// including "not configured" and "not installed", which are answers, not gaps.

struct InternetStatus: Equatable {
    var reachable: Bool?
    var latencyMs: Double?
    var target: String = "1.1.1.1:443"
    var checkedAt = Date()

    var summary: String {
        switch reachable {
        case .some(true): return latencyMs.map { String(format: "reachable · %.0f ms", $0) } ?? "reachable"
        case .some(false): return "no route to \(target)"
        case nil: return "not checked"
        }
    }
}

struct Tunnel: Equatable, Identifiable {
    var id: String { interface }
    var interface: String
    var ipv4: String?
    var mtu: Int?
    /// Tailscale owns one utun; saying so stops it being read as a second VPN.
    var isTailscale: Bool
}

struct VPNStatus: Equatable {
    /// Configured VPN services from `scutil --nc list`, with their state.
    var services: [ConfiguredVPN] = []
    var tunnels: [Tunnel] = []
    var checkedAt = Date()

    struct ConfiguredVPN: Equatable, Identifiable {
        var id: String { name }
        var name: String
        var state: String
        var enabled: Bool
        var connected: Bool { state.lowercased().contains("connected") && !state.lowercased().contains("dis") }
    }

    var connectedService: ConfiguredVPN? { services.first(where: \.connected) }

    var summary: String {
        if let connected = connectedService { return "\(connected.name) connected" }
        if services.isEmpty {
            let others = tunnels.filter { !$0.isTailscale }
            return others.isEmpty ? "none configured" : "\(others.count) system tunnel(s), no VPN configured"
        }
        return "\(services.count) configured · none connected"
    }
}

struct VLANStatus: Equatable {
    var interfaces: [String] = []
    var checkedAt = Date()
    var summary: String { interfaces.isEmpty ? "none configured" : interfaces.joined(separator: ", ") }
}

struct ThunderboltPort: Equatable, Identifiable {
    var id: String { device }
    var name: String
    var device: String
    var active: Bool
    var ipv4: String?
}

struct ThunderboltStatus: Equatable {
    var ports: [ThunderboltPort] = []
    var checkedAt = Date()

    var activePorts: [ThunderboltPort] { ports.filter(\.active) }

    var summary: String {
        if ports.isEmpty { return "no Thunderbolt ports" }
        let active = activePorts
        if active.isEmpty { return "\(ports.count) ports · none linked" }
        return active.map { $0.ipv4 ?? $0.device }.joined(separator: ", ")
    }
}

struct ExoStatus: Equatable {
    var installed = false
    var executablePath: String?
    var processCount = 0
    var endpointReachable: Bool?
    var endpoint = "127.0.0.1:52415"
    var checkedAt = Date()

    var summary: String {
        if endpointReachable == true { return "node answering on \(endpoint)" }
        if processCount > 0 { return "\(processCount) process(es), endpoint not answering" }
        if installed { return "installed, not running" }
        return "not installed"
    }

    var tone: StatusTone {
        if endpointReachable == true { return .good }
        if processCount > 0 { return .warn }
        return .unknown
    }
}

enum ConnectionProbes {

    /// A TCP connect to a well-known host. This is the only probe in FleetConsole
    /// that leaves the machine by default, it is a bare TCP handshake carrying no
    /// data, and the target is configurable.
    static func internet(target: String = "1.1.1.1:443", timeout: TimeInterval = 2) -> InternetStatus {
        var status = InternetStatus(target: target)
        let parts = target.split(separator: ":")
        guard parts.count == 2, let port = Int(parts[1]) else {
            status.reachable = false
            return status
        }
        let result = TCPProbe.connect(host: String(parts[0]), port: port, timeout: timeout)
        status.reachable = result.ok
        status.latencyMs = result.ok ? result.latencyMs : nil
        return status
    }

    static func vpn(tailscaleIPv4: String?) -> VPNStatus {
        var status = VPNStatus()

        // Configured services, e.g. "* (Disconnected)   ABC-123 PPP (L2TP) "Work" [...]"
        let listed = Shell.run("/usr/sbin/scutil", ["--nc", "list"], timeout: 6)
        for line in listed.stdout.split(separator: "\n") {
            guard let open = line.firstIndex(of: "("), let close = line.firstIndex(of: ")"),
                  open < close else { continue }
            let state = String(line[line.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            // The service name is the quoted field.
            let quoted = line.split(separator: "\"")
            guard quoted.count >= 2 else { continue }
            status.services.append(VPNStatus.ConfiguredVPN(name: String(quoted[1]),
                                                           state: state,
                                                           enabled: line.hasPrefix("*")))
        }

        // Active tunnel interfaces, with Tailscale's identified so it is not
        // double-counted as "a VPN you did not know about".
        for (interface, ipv4) in Self.tunnelInterfaces() {
            status.tunnels.append(Tunnel(interface: interface,
                                         ipv4: ipv4,
                                         mtu: nil,
                                         isTailscale: ipv4 != nil && ipv4 == tailscaleIPv4))
        }
        return status
    }

    static func tunnelInterfaces() -> [(String, String?)] {
        var found: [(String, String?)] = []
        let output = Shell.run("/sbin/ifconfig", ["-a"], timeout: 6).stdout
        var current: String?
        for raw in output.split(separator: "\n") {
            if !raw.hasPrefix("\t") && !raw.hasPrefix(" ") {
                let name = String(raw.split(separator: ":").first ?? "")
                current = (name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp")) ? name : nil
                if let current, !found.contains(where: { $0.0 == current }) {
                    found.append((current, nil))
                }
            } else if let current, raw.trimmingCharacters(in: .whitespaces).hasPrefix("inet ") {
                let address = raw.trimmingCharacters(in: .whitespaces)
                    .split(separator: " ").dropFirst().first.map(String.init)
                if let index = found.firstIndex(where: { $0.0 == current }) {
                    found[index].1 = address
                }
            }
        }
        return found
    }

    static func vlan() -> VLANStatus {
        var status = VLANStatus()
        let output = Shell.run("/usr/sbin/networksetup", ["-listVLANs"], timeout: 6).stdout
        if output.contains("no VLANs") { return status }
        for line in output.split(separator: "\n") where line.hasPrefix("VLAN User Defined Name:") {
            status.interfaces.append(String(line.dropFirst("VLAN User Defined Name:".count))
                .trimmingCharacters(in: .whitespaces))
        }
        // Fall back to interface names if the friendly names were not printed.
        if status.interfaces.isEmpty {
            let ifconfig = Shell.run("/sbin/ifconfig", ["-a"], timeout: 6).stdout
            for raw in ifconfig.split(separator: "\n") where raw.hasPrefix("vlan") {
                status.interfaces.append(String(raw.split(separator: ":").first ?? ""))
            }
        }
        return status
    }

    static func thunderbolt(hardwarePorts: [String: String]) -> ThunderboltStatus {
        var status = ThunderboltStatus()
        for (name, device) in hardwarePorts where name.lowercased().contains("thunderbolt") {
            let ifconfig = Shell.run("/sbin/ifconfig", [device], timeout: 4).stdout
            let active = ifconfig.contains("status: active")
            status.ports.append(ThunderboltPort(name: name,
                                                device: device,
                                                active: active,
                                                ipv4: NetworkMonitor.ipv4Address(for: device)))
        }
        status.ports.sort { $0.device < $1.device }
        return status
    }

    /// exo (the distributed inference cluster). Reports what is actually present:
    /// a binary, running processes, and whether its local endpoint answers. No
    /// cluster details are claimed that were not observed.
    static func exo(endpoint: String = "127.0.0.1:52415", table: ProcessTable? = nil) -> ExoStatus {
        var status = ExoStatus(endpoint: endpoint)
        status.executablePath = Shell.which("exo", candidates: [
            "/usr/local/bin/exo", "/opt/homebrew/bin/exo",
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/exo"),
        ])
        status.installed = status.executablePath != nil
            || FileManager.default.fileExists(atPath: (NSHomeDirectory() as NSString).appendingPathComponent(".exo"))

        let processes = table ?? ProcessTable.capture(includeListeners: false)
        status.processCount = processes.byPID.values.filter { proc in
            let line = proc.commandLine.lowercased()
            return line.contains("exo/main.py") || line.contains("exo.main")
                || proc.executableName == "exo" || line.contains("/exo ")
        }.count

        let parts = endpoint.split(separator: ":")
        if parts.count == 2, let port = Int(parts[1]) {
            status.endpointReachable = TCPProbe.connect(host: String(parts[0]), port: port, timeout: 1).ok
        }
        return status
    }
}
