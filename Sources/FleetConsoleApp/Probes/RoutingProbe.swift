import Foundation
import FleetCore

struct Subnet: Codable, Equatable, Sendable {
    var network: String
    var prefixLength: Int

    var cidr: String { "\(network)/\(prefixLength)" }

    static func isPrivate(_ address: String) -> Bool {
        if address.hasPrefix("10.") || address.hasPrefix("192.168.") || address.hasPrefix("127.")
            || address.hasPrefix("169.254.") || address.hasPrefix("::1")
            || address.lowercased().hasPrefix("fe80:") || address.lowercased().hasPrefix("fd") {
            return true
        }
        let parts = address.split(separator: ".")
        if parts.count == 4, parts[0] == "172", let second = Int(parts[1]), (16...31).contains(second) {
            return true
        }
        if parts.count == 4, parts[0] == "100", let second = Int(parts[1]), (64...127).contains(second) {
            return true
        }
        return false
    }
}

struct NetworkSegment: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var vlanTag: Int?
    var cidr: String?
    var gateway: String?
    var purpose: String?
}

struct NetworkInterface: Identifiable, Codable, Equatable, Sendable {
    var id: String { bsdName }

    var bsdName: String
    var displayName: String
    var kind: Kind
    var isUp: Bool
    var hasLink: Bool
    var ipv4: [String]
    var ipv6: [String]
    var macAddress: String?
    var mtu: Int?
    var subnet: Subnet?

    var vlanTag: Int?
    var vlanParent: String?
    var segment: NetworkSegment?

    enum Kind: String, Codable, Sendable {
        case wifi, ethernet, thunderbolt, bridge, tunnel, vlan, loopback, other

        var symbol: String {
            switch self {
            case .wifi: return "wifi"
            case .ethernet: return "cable.connector"
            case .thunderbolt: return "bolt.horizontal"
            case .bridge: return "arrow.triangle.branch"
            case .tunnel: return "lock.shield"
            case .vlan: return "rectangle.3.group"
            case .loopback: return "arrow.uturn.left"
            case .other: return "network"
            }
        }
    }

    var routableIPv6: [String] { ipv6.filter { !$0.lowercased().hasPrefix("fe80:") } }

    var primaryAddress: String? { ipv4.first ?? routableIPv6.first }

    var isSelfAssigned: Bool {
        !ipv4.isEmpty && ipv4.allSatisfy { $0.hasPrefix("169.254.") }
    }

    var hasCarrier: Bool {
        switch kind {
        case .wifi, .ethernet, .thunderbolt: return true
        case .tunnel, .vlan, .bridge, .loopback, .other: return false
        }
    }

    var tone: StatusTone {
        if isSelfAssigned { return .warn }
        if hasCarrier {
            if hasLink { return .good }
            return primaryAddress == nil ? .neutral : .warn
        }
        return primaryAddress == nil ? .neutral : .good
    }

    var statusLabel: String {
        if isSelfAssigned { return "self-assigned, no DHCP" }
        if hasCarrier {
            if hasLink { return primaryAddress == nil ? "link, no address" : "link active" }
            return isUp ? "no link" : "down"
        }
        return primaryAddress == nil ? "no address" : "up"
    }

    var isInteresting: Bool {
        if kind == .loopback { return false }
        if !ipv4.isEmpty || !routableIPv6.isEmpty || vlanTag != nil { return true }
        switch kind {
        case .wifi, .ethernet, .thunderbolt: return hasLink
        default: return false
        }
    }
}

struct DefaultRoute: Codable, Equatable, Sendable, Identifiable {
    var gateway: String?
    var interface: String
    var isIPv6: Bool
    var isPrimary: Bool

    var id: String { "\(interface)-\(isIPv6 ? "v6" : "v4")-\(gateway ?? "link")" }
}

struct RoutingStatus: Codable, Equatable, Sendable {
    var routes: [DefaultRoute] = []
    var resolvers: [String] = []
    var searchDomains: [String] = []
    var interfaces: [NetworkInterface] = []
    var checkedAt = Date()

    var primaryRoute: DefaultRoute? { routes.first { $0.isPrimary && !$0.isIPv6 } ?? routes.first { $0.isPrimary } }
    var defaultGatewayIPv4: String? { routes.first { $0.isPrimary && !$0.isIPv6 }?.gateway }
    var defaultGatewayIPv6: String? { routes.first { $0.isPrimary && $0.isIPv6 }?.gateway }
    var defaultInterface: String? { primaryRoute?.interface }

    var secondaryRoutes: [DefaultRoute] { routes.filter { !$0.isPrimary } }

    func route(forInterface bsdName: String) -> DefaultRoute? {
        routes.first { $0.interface == bsdName && !$0.isIPv6 }
            ?? routes.first { $0.interface == bsdName }
    }

    var gatewayInterface: NetworkInterface? {
        defaultInterface.flatMap { name in interfaces.first { $0.bsdName == name } }
    }

    func sameContent(as other: RoutingStatus) -> Bool {
        routes == other.routes
            && resolvers == other.resolvers
            && searchDomains == other.searchDomains
            && interfaces == other.interfaces
    }

    var summary: String {
        guard let primary = primaryRoute else { return "no default route" }
        let gateway = primary.gateway ?? primary.interface
        let label = interfaces.first { $0.bsdName == primary.interface }?.displayName
            ?? primary.interface
        var text = "\(gateway) via \(label)"
        let others = secondaryRoutes.filter { !$0.isIPv6 }.count
        if others > 0 { text += " +\(others)" }
        return text
    }

    func displayName(ofInterface bsdName: String) -> String {
        interfaces.first { $0.bsdName == bsdName }?.displayName ?? bsdName
    }

    var resolverSummary: String {
        if resolvers.isEmpty { return "none configured" }
        if resolvers.count == 1 { return resolvers[0] }
        return "\(resolvers[0]) +\(resolvers.count - 1)"
    }
}

enum RoutingProbe {

    nonisolated static func capture(hardwarePorts: [String: String]) -> RoutingStatus {
        var status = RoutingStatus()
        status.routes = defaultRoutes()
        let dns = resolvers()
        status.resolvers = dns.servers
        status.searchDomains = dns.domains
        status.interfaces = interfaces(hardwarePorts: hardwarePorts)
        return status
    }

    nonisolated static func defaultRoutes() -> [DefaultRoute] {
        var found: [DefaultRoute] = []
        for family in ["inet", "inet6"] {
            let isIPv6 = family == "inet6"
            var seenPrimary = false
            let output = Shell.run("/usr/sbin/netstat", ["-rn", "-f", family], timeout: 6).stdout
            for raw in output.split(separator: "\n") {
                let fields = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard fields.count >= 2, fields[0] == "default", let interface = fields.last else {
                    continue
                }
                let gateway = fields[1]
                let looksLikeAddress = gateway.contains(".") || gateway.contains(":")
                found.append(DefaultRoute(gateway: looksLikeAddress ? gateway : nil,
                                          interface: interface,
                                          isIPv6: isIPv6,
                                          isPrimary: !seenPrimary))
                seenPrimary = true
            }
        }
        return found
    }

    nonisolated static func resolvers() -> (servers: [String], domains: [String]) {
        let output = Shell.run("/usr/sbin/scutil", ["--dns"], timeout: 6).stdout
        var servers: [String] = []
        var domains: [String] = []
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("DNS configuration (for scoped queries)") { break }
            if line.hasPrefix("nameserver[") {
                if let value = line.split(separator: ":", maxSplits: 1).last {
                    let server = value.trimmingCharacters(in: .whitespaces)
                    if !server.isEmpty, !servers.contains(server) { servers.append(server) }
                }
            } else if line.hasPrefix("search domain[") {
                if let value = line.split(separator: ":", maxSplits: 1).last {
                    let domain = value.trimmingCharacters(in: .whitespaces)
                    if !domain.isEmpty, !domains.contains(domain) { domains.append(domain) }
                }
            }
        }
        return (servers, domains)
    }

    nonisolated static func interfaces(hardwarePorts: [String: String]) -> [NetworkInterface] {
        var namesByDevice: [String: String] = [:]
        for (name, device) in hardwarePorts { namesByDevice[device] = name }

        let output = Shell.run("/sbin/ifconfig", ["-a"], timeout: 8).stdout
        var result: [NetworkInterface] = []
        var current: NetworkInterface?

        func flush() {
            if let interface = current { result.append(interface) }
            current = nil
        }

        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let isHeader = !raw.hasPrefix("\t") && !raw.hasPrefix(" ") && raw.contains(":")
            if isHeader {
                flush()
                let name = String(raw.split(separator: ":", maxSplits: 1)[0])
                guard !name.isEmpty else { continue }
                var interface = NetworkInterface(
                    bsdName: name,
                    displayName: namesByDevice[name] ?? name,
                    kind: kind(for: name, displayName: namesByDevice[name]),
                    isUp: raw.contains("<UP,") || raw.contains(",UP,") || raw.contains("UP,"),
                    hasLink: false,
                    ipv4: [], ipv6: [],
                    macAddress: nil, mtu: nil, subnet: nil)
                if let mtuRange = raw.range(of: "mtu ") {
                    interface.mtu = Int(raw[mtuRange.upperBound...].prefix { $0.isNumber })
                }
                current = interface
                continue
            }

            guard var interface = current else { continue }
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("inet ") {
                let fields = line.split(separator: " ").map(String.init)
                if fields.count >= 2 {
                    interface.ipv4.append(fields[1])
                    if let maskIndex = fields.firstIndex(of: "netmask"), maskIndex + 1 < fields.count,
                       let prefix = prefixLength(fromHexNetmask: fields[maskIndex + 1]) {
                        interface.subnet = Subnet(network: networkAddress(of: fields[1], prefix: prefix),
                                                  prefixLength: prefix)
                    }
                }
            } else if line.hasPrefix("inet6 ") {
                let fields = line.split(separator: " ").map(String.init)
                if fields.count >= 2 {
                    interface.ipv6.append(String(fields[1].split(separator: "%")[0]))
                }
            } else if line.hasPrefix("ether ") {
                interface.macAddress = line.split(separator: " ").dropFirst().first.map(String.init)
            } else if line.hasPrefix("status:") {
                let value = line.dropFirst("status:".count).trimmingCharacters(in: .whitespaces)
                interface.hasLink = value == "active"
            } else if line.hasPrefix("vlan:") {
                let fields = line.split(separator: " ").map(String.init)
                if fields.count >= 2 { interface.vlanTag = Int(fields[1]) }
                if let parentIndex = fields.firstIndex(of: "interface:"), parentIndex + 1 < fields.count {
                    let parent = fields[parentIndex + 1]
                    interface.vlanParent = parent == "<none>" ? nil : parent
                }
            }
            current = interface
        }
        flush()

        return result.sorted { left, right in
            if left.isInteresting != right.isInteresting { return left.isInteresting }
            return left.bsdName.localizedStandardCompare(right.bsdName) == .orderedAscending
        }
    }

    nonisolated static func kind(for name: String, displayName: String?) -> NetworkInterface.Kind {
        let label = (displayName ?? "").lowercased()
        if name.hasPrefix("lo") { return .loopback }
        if name.hasPrefix("vlan") { return .vlan }
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") { return .tunnel }
        if name.hasPrefix("bridge") { return .bridge }
        if label.contains("wi-fi") || label.contains("airport") { return .wifi }
        if label.contains("thunderbolt") { return .thunderbolt }
        if label.contains("ethernet") || label.contains("lan") { return .ethernet }
        if name.hasPrefix("en") { return .ethernet }
        return .other
    }

    nonisolated static func prefixLength(fromHexNetmask hex: String) -> Int? {
        var text = hex.lowercased()
        if text.hasPrefix("0x") { text.removeFirst(2) }
        guard let value = UInt32(text, radix: 16) else { return nil }
        return value.nonzeroBitCount
    }

    nonisolated static func networkAddress(of address: String, prefix: Int) -> String {
        let octets = address.split(separator: ".").compactMap { UInt32($0) }
        guard octets.count == 4, (0...32).contains(prefix) else { return address }
        let packed = (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]
        let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << (32 - prefix)
        let network = packed & mask
        return "\((network >> 24) & 0xff).\((network >> 16) & 0xff).\((network >> 8) & 0xff).\(network & 0xff)"
    }
}
