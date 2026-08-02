import Foundation
import FleetCore

// Where this machine's packets go, and who it asks for names.
//
// The connection surfaces already covered *link* state — is Wi-Fi associated, is
// the wire up, is Tailscale running. They did not cover the two facts you
// actually reach for when something is broken: the default gateway and the
// resolvers. This probe adds those, plus the interface inventory the two of them
// index into.
//
// Read-only, like every other probe here. `netstat`, `ifconfig` and `scutil` are
// queried; nothing is configured. Everything is `Codable`, because the support
// bundle is a serialisation of this model rather than a second implementation of
// it — a diagnostic that can drift from the screen it claims to describe is worth
// less than no diagnostic.

// MARK: - Model

/// A subnet, kept as its parts rather than as a formatted string, so a caller
/// that needs the prefix length does not have to parse the label back apart.
struct Subnet: Codable, Equatable, Sendable {
    var network: String
    var prefixLength: Int

    var cidr: String { "\(network)/\(prefixLength)" }

    /// RFC 1918 / RFC 4193 / link-local. The support-bundle sanitiser keeps
    /// these and masks everything else: a private address describes your own
    /// topology, a public one identifies you.
    static func isPrivate(_ address: String) -> Bool {
        if address.hasPrefix("10.") || address.hasPrefix("192.168.") || address.hasPrefix("127.")
            || address.hasPrefix("169.254.") || address.hasPrefix("::1")
            || address.lowercased().hasPrefix("fe80:") || address.lowercased().hasPrefix("fd") {
            return true
        }
        // 172.16.0.0/12 is the one that needs arithmetic rather than a prefix.
        let parts = address.split(separator: ".")
        if parts.count == 4, parts[0] == "172", let second = Int(parts[1]), (16...31).contains(second) {
            return true
        }
        // Tailscale's CGNAT range. Not RFC 1918, but it is overlay-internal and
        // reveals nothing about where you are.
        if parts.count == 4, parts[0] == "100", let second = Int(parts[1]), (64...127).contains(second) {
            return true
        }
        return false
    }
}

/// A VLAN segment, as an administrative object rather than as a local interface.
///
/// Nothing populates this today: the host's own 802.1Q interfaces carry a tag and
/// a parent (both real, both read off `ifconfig`), but a *segment* — its name, its
/// CIDR, its gateway, what it is for — is knowledge a switch or a controller has
/// and this machine does not. That is what `VLANSource` is for. Until one is
/// registered the field is `nil` and no segment UI renders.
struct NetworkSegment: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var vlanTag: Int?
    var cidr: String?
    var gateway: String?
    var purpose: String?
}

/// One interface, as the app models it.
///
/// The three VLAN fields are the forward-looking part. `vlanTag` and `vlanParent`
/// are populated for real from `ifconfig` on any host that has an 802.1Q
/// interface configured; `segment` is the seam a `VLANSource` fills. All three
/// are optional and every renderer treats `nil` as *absent*, not as *unknown* —
/// so a machine with no VLANs shows no VLAN chrome at all.
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

    // MARK: VLAN-ready
    var vlanTag: Int?
    var vlanParent: String?
    var segment: NetworkSegment?

    enum Kind: String, Codable, Sendable {
        case wifi, ethernet, thunderbolt, bridge, tunnel, vlan, loopback, other

        /// Identity, not state — the same rule every row icon in the app follows.
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

    /// Addresses something else can reach. A `fe80::` is auto-configured on
    /// essentially every interface macOS brings up and reaches exactly one link,
    /// so it is not an address in the sense this section means.
    var routableIPv6: [String] { ipv6.filter { !$0.lowercased().hasPrefix("fe80:") } }

    /// The address a human means when they say "my IP on this interface".
    var primaryAddress: String? { ipv4.first ?? routableIPv6.first }

    /// A `169.254.x.x` address is what macOS assigns itself when DHCP does not
    /// answer. The interface is up, the cable is in, and it is on a network of
    /// one — which is a *fault*, not a working link, and rendering it the same
    /// green as a real lease is the third version of the same mistake this file
    /// has already made twice (`inactive` matching `active`, and `fe80::`
    /// counting as an address).
    var isSelfAssigned: Bool {
        !ipv4.isEmpty && ipv4.allSatisfy { $0.hasPrefix("169.254.") }
    }

    /// Whether "link" is a meaningful question for this kind of interface.
    ///
    /// `ifconfig` prints `status:` for hardware ports and omits it for tunnels,
    /// bridges and loopback — there is no carrier to report. Treating that
    /// absence as *no link* renders a working Tailscale tunnel amber, which is
    /// the app claiming a fault where the field simply does not apply.
    var hasCarrier: Bool {
        switch kind {
        case .wifi, .ethernet, .thunderbolt: return true
        case .tunnel, .vlan, .bridge, .loopback, .other: return false
        }
    }

    /// The row tone. A carrier interface is judged on its link; everything else
    /// on whether it carries a routable address, which for a tunnel is the whole
    /// of what "up" means.
    var tone: StatusTone {
        // A self-assigned address outranks link state: the carrier is fine and
        // the interface still cannot reach anything.
        if isSelfAssigned { return .warn }
        if hasCarrier {
            if hasLink { return .good }
            return primaryAddress == nil ? .neutral : .warn
        }
        return primaryAddress == nil ? .neutral : .good
    }

    /// The status in words, written once so the row subtitle and the expanded
    /// detail cannot describe the same interface differently.
    var statusLabel: String {
        if isSelfAssigned { return "self-assigned, no DHCP" }
        if hasCarrier {
            if hasLink { return primaryAddress == nil ? "link, no address" : "link active" }
            return isUp ? "no link" : "down"
        }
        return primaryAddress == nil ? "no address" : "up"
    }

    /// Interfaces with no address and no link are the long tail of `ifconfig -a`
    /// — `gif0`, `stf0`, `awdl0` when idle, a dozen `utun`s macOS keeps spare.
    /// Listing them is not thoroughness; it is burying the four that matter.
    ///
    /// The bar is a **routable** address, a VLAN tag, or a live link on a port
    /// you could plug something into. Link-local alone does not qualify: this
    /// machine has 26 interfaces and 22 of them carry an `fe80::` — an earlier
    /// version accepted `!ipv6.isEmpty` and listed all 22, which is the exact
    /// failure the paragraph above describes, committed by the filter written to
    /// prevent it.
    ///
    /// A linked port with no address is kept on purpose, and only for the kinds
    /// you physically attach to: a plugged-in Ethernet port that never got a
    /// lease is one of the more useful things this section can show you.
    var isInteresting: Bool {
        if kind == .loopback { return false }
        if !ipv4.isEmpty || !routableIPv6.isEmpty || vlanTag != nil { return true }
        switch kind {
        case .wifi, .ethernet, .thunderbolt: return hasLink
        default: return false
        }
    }
}

/// One default route. A multi-homed machine has several, and which one wins is
/// a separate fact from which ones exist.
struct DefaultRoute: Codable, Equatable, Sendable, Identifiable {
    var gateway: String?
    var interface: String
    var isIPv6: Bool
    /// The route macOS is actually using for this family — the first one
    /// `netstat` prints, which is service order.
    var isPrimary: Bool

    var id: String { "\(interface)-\(isIPv6 ? "v6" : "v4")-\(gateway ?? "link")" }
}

/// The routing and resolver picture, plus the interfaces it refers to.
struct RoutingStatus: Codable, Equatable, Sendable {
    /// Every default route, in the order `netstat` prints them. The first per
    /// family is the one in use.
    ///
    /// This used to be a single gateway and a single interface, because the
    /// parser took the first `default` line and stopped. On a machine attached
    /// to two networks at once — a wired LAN and a segmented wireless one, which
    /// is an ordinary way to be set up — that reported one of two answers and
    /// gave no sign there was another. "Where do my packets go" has as many
    /// answers as there are default routes; the app's job is to say which one
    /// wins, not to pretend the others do not exist.
    var routes: [DefaultRoute] = []
    /// The interface the winning route leaves by — the answer to "which link am
    /// I actually using", which is not always the one that looks connected.
    var resolvers: [String] = []
    var searchDomains: [String] = []
    var interfaces: [NetworkInterface] = []
    var checkedAt = Date()

    var primaryRoute: DefaultRoute? { routes.first { $0.isPrimary && !$0.isIPv6 } ?? routes.first { $0.isPrimary } }
    var defaultGatewayIPv4: String? { routes.first { $0.isPrimary && !$0.isIPv6 }?.gateway }
    var defaultGatewayIPv6: String? { routes.first { $0.isPrimary && $0.isIPv6 }?.gateway }
    var defaultInterface: String? { primaryRoute?.interface }

    /// Routes that exist but are not the one in use. Named rather than derived
    /// at the call site because "you have a second way out and it is not the one
    /// being used" is the fact this section exists to surface.
    var secondaryRoutes: [DefaultRoute] { routes.filter { !$0.isPrimary } }

    func route(forInterface bsdName: String) -> DefaultRoute? {
        routes.first { $0.interface == bsdName && !$0.isIPv6 }
            ?? routes.first { $0.interface == bsdName }
    }

    var gatewayInterface: NetworkInterface? {
        defaultInterface.flatMap { name in interfaces.first { $0.bsdName == name } }
    }

    /// Everything except the timestamp.
    ///
    /// This snapshot carries the whole interface inventory, and `checkedAt` moves
    /// on every pass by construction — so a plain `!=` is true every single time
    /// and reassigning on it would invalidate an `@Observable` array of a dozen
    /// interfaces every refresh interval, forever, whether or not a single byte
    /// of it changed. The comparison that decides whether to publish has to be
    /// the content.
    ///
    /// The consequence is deliberate and is why the UI labels this **As of**
    /// rather than *Checked*: the timestamp on screen is when this picture was
    /// established, not when the probe last ran. Those differ exactly when
    /// nothing has changed, which is the case where the distinction costs
    /// nothing and the redraw would have been free of information.
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
        // The count of *other* ways out, stated. A second default route is
        // invisible on a machine that is working and is the first thing you want
        // to know on one that is not. Written `+2` rather than `· +2 more`,
        // because this line sits in a 380pt row behind an icon and the long form
        // truncated the interface name it exists to report.
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

// MARK: - Probe

enum RoutingProbe {

    /// One pass: routes, resolvers, interfaces. Called on a background queue —
    /// it forks three tools and parses their output, which is not main-thread
    /// work.
    nonisolated static func capture(hardwarePorts: [String: String]) -> RoutingStatus {
        var status = RoutingStatus()
        status.routes = defaultRoutes()
        let dns = resolvers()
        status.resolvers = dns.servers
        status.searchDomains = dns.domains
        status.interfaces = interfaces(hardwarePorts: hardwarePorts)
        return status
    }

    // MARK: Routes

    /// `netstat -rn` for both families. The IPv4 default line looks like:
    ///
    ///     default            192.168.1.1        UGScg            en0
    ///
    /// The interface is taken from the v4 route when there is one, because that
    /// is the family almost everything on a LAN actually uses; the v6 gateway is
    /// still reported beside it.
    /// **Every** default line, not the first.
    ///
    /// The earlier version `break`ed out of the loop on the first match per
    /// family, which is correct only on a singly-homed machine. Attach to a
    /// wired LAN and a segmented wireless network at once and `netstat` prints
    /// two, of which macOS uses the first by service order — the parser reported
    /// that one and gave no sign the other existed.
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
                // A gateway that is an interface name rather than an address is
                // a point-to-point link (`default  link#22  UCSIg  utun4`).
                // Real, but not something you can ping, so it is carried as a
                // route with no gateway rather than as a fake address.
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

    // MARK: DNS

    /// `scutil --dns` prints the resolver list twice — once for general queries
    /// and again under "DNS configuration (for scoped queries)", where every
    /// interface repeats its own copy. Only the first block is read: the scoped
    /// section would list the same three servers four times and read as a
    /// misconfiguration.
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

    // MARK: Interfaces

    /// `ifconfig -a`, parsed into the model. The display names come from
    /// `networksetup -listallhardwareports`, which is the only place macOS says
    /// that `en0` is called "Wi-Fi".
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
                    // The zone suffix (`fe80::1%en0`) names the interface we are
                    // already inside, so it is noise in this position.
                    interface.ipv6.append(String(fields[1].split(separator: "%")[0]))
                }
            } else if line.hasPrefix("ether ") {
                interface.macAddress = line.split(separator: " ").dropFirst().first.map(String.init)
            } else if line.hasPrefix("status:") {
                // Compared, not `contains`. `ifconfig` prints exactly two values
                // here and one of them is **inactive**, which contains the
                // string "active" — so a substring test reports link on every
                // interface that has none. That is not hypothetical: the first
                // render of this section listed 22 of 26 interfaces as linked,
                // including three empty Thunderbolt ports and eight spare
                // tunnels, because of this one word.
                let value = line.dropFirst("status:".count).trimmingCharacters(in: .whitespaces)
                interface.hasLink = value == "active"
            } else if line.hasPrefix("vlan:") {
                // `vlan: 40 parent interface: en0` — a real 802.1Q tag, read off
                // the host. This is the one VLAN fact this machine genuinely
                // knows about itself.
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
            // Addressed and linked first, then by name, so `en0` leads and the
            // spare tunnels sink whatever order ifconfig happened to print.
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

    /// `ifconfig` prints the mask as `0xffffff00`. Counting bits is the whole
    /// conversion; the leading-`0x` form is the only one it emits.
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
