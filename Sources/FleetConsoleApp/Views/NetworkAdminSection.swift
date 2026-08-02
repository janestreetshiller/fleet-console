import SwiftUI
import AppKit
import FleetCore

/// The administration half of the Network tab: routing, resolvers, interfaces,
/// and the verbs that go with them.
///
/// The existing rows answer *what am I attached to* — Wi-Fi, wire, Tailscale,
/// VPN. This answers the two questions you ask next when something is wrong:
/// **where do my packets go** and **who do I ask for names**. Both were missing
/// entirely, which meant the surface could tell you the Wi-Fi was associated and
/// could not tell you the gateway had stopped answering.
///
/// Every verb here is read-only or clipboard-only, and the diagnostics run off
/// the main actor with a hard deadline — see `NetworkActions`.
struct NetworkAdminSection: View {
    @Bindable var model: AppModel
    @Binding var expanded: String?

    private var net: NetworkMonitor { model.network }
    private var routing: RoutingStatus { model.network.routing }
    private var actions: NetworkActions { model.actions }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CompactHeader(title: "Routing")
            gatewayRow
            dnsRow

            CompactHeader(title: "Interfaces", trailing: interfaceCountLabel)
            if interfaces.isEmpty {
                EmptyLine(text: "no interface has an address")
            } else {
                ForEach(interfaces) { interface in
                    interfaceRow(interface)
                }
            }

            // Segments render only when a source has told us about some. No
            // source registered → no header, no empty state, no row. See
            // `VLANSource` for why an empty state would be a claim we cannot
            // make.
            if VLANRegistry.shared.isAvailable {
                segmentSection
            }

            if let outcome = actions.lastOutcome {
                diagnosticOutput(outcome)
            }
        }
    }

    private var interfaces: [NetworkInterface] {
        routing.interfaces.filter(\.isInteresting)
    }

    private var interfaceCountLabel: String? {
        let total = routing.interfaces.count
        let shown = interfaces.count
        guard total > 0 else { return nil }
        return shown == total ? "\(total)" : "\(shown) of \(total)"
    }

    // MARK: - Gateway

    private var gatewayRow: some View {
        let gateway = routing.defaultGatewayIPv4 ?? routing.defaultGatewayIPv6
        return DisclosureRow(id: "gateway", expanded: $expanded) {
            FleetRowLabel(icon: "arrow.triangle.turn.up.right.diamond",
                          tone: gateway == nil ? .bad : .good,
                          title: "Default gateway",
                          subtitle: routing.summary,
                          inlineSubtitle: true)
        } detail: {
            VStack(alignment: .leading, spacing: 3) {
                // Every default route, with the one in use marked. A machine on
                // two networks at once has two answers to "where do my packets
                // go", and listing only the winner hides the fact that there is
                // a second — which is the first thing you want to know when the
                // winner stops working.
                if routing.routes.isEmpty {
                    KeyValue(key: "Routes", value: "no default route")
                } else {
                    ForEach(routing.routes) { route in
                        KeyValue(key: route.isPrimary ? "In use" : "Also",
                                 value: (route.gateway ?? "link")
                                    + "  via \(routing.displayName(ofInterface: route.interface))"
                                    + (route.isIPv6 ? "  (IPv6)" : ""),
                                 monospaced: true)
                    }
                }
                if let subnet = routing.gatewayInterface?.subnet {
                    KeyValue(key: "Subnet", value: subnet.cidr, monospaced: true)
                }
                // "As of", not "Checked": the snapshot is only republished when
                // its content changes, so this is when the picture was
                // established. See `RoutingStatus.sameContent(as:)`.
                KeyValue(key: "As of", value: Fmt.relative(routing.checkedAt))

                if let gateway {
                    RowActions {
                        Button("Copy") { actions.copy(gateway, label: "gateway address") }
                        Button(actions.running == nil ? "Ping" : "Pinging…") {
                            actions.pingGateway(gateway)
                        }
                        .disabled(actions.isRunning)
                        Button("Traceroute") { actions.traceroute(gateway) }
                            .disabled(actions.isRunning)
                    }
                } else {
                    RowActions {
                        Button("Open Network Settings") { net.openSettings(.network) }
                    }
                }
            }
        }
    }

    // MARK: - DNS

    private var dnsRow: some View {
        DisclosureRow(id: "dns", expanded: $expanded) {
            FleetRowLabel(icon: "character.book.closed",
                          tone: routing.resolvers.isEmpty ? .warn : .good,
                          title: "DNS",
                          subtitle: routing.resolverSummary,
                          inlineSubtitle: true)
        } detail: {
            VStack(alignment: .leading, spacing: 3) {
                if routing.resolvers.isEmpty {
                    KeyValue(key: "Resolvers", value: "none configured")
                } else {
                    ForEach(Array(routing.resolvers.enumerated()), id: \.offset) { index, server in
                        KeyValue(key: index == 0 ? "Primary" : "Resolver \(index + 1)",
                                 // `100.100.100.100` is Tailscale's MagicDNS and
                                 // nothing else — a fixed address the daemon
                                 // installs. Saying so turns a resolver nobody
                                 // recognises into the one fact that explains
                                 // why name resolution still works on a segment
                                 // whose own DNS is unreachable.
                                 value: server + (isMagicDNS(server) ? "  (Tailscale MagicDNS)" : ""),
                                 monospaced: true)
                    }
                }
                if routing.searchDomains.isEmpty {
                    KeyValue(key: "Search domains", value: "none")
                } else {
                    KeyValue(key: "Search domains",
                             value: routing.searchDomains.joined(separator: ", "),
                             monospaced: true)
                }
                KeyValue(key: "As of", value: Fmt.relative(routing.checkedAt))
                RowActions {
                    if let primary = routing.resolvers.first {
                        Button("Copy") { actions.copy(primary, label: "DNS resolver") }
                        Button("Ping") { actions.pingGateway(primary) }
                            .disabled(actions.isRunning)
                    }
                    Button("Open Network Settings") { net.openSettings(.network) }
                }
            }
        }
    }

    /// Tailscale's resolver addresses, both families. Fixed values the daemon
    /// installs, so this is recognition rather than a heuristic.
    private func isMagicDNS(_ server: String) -> Bool {
        server == "100.100.100.100" || server.lowercased().hasPrefix("fd7a:115c:a1e0:")
    }

    // MARK: - Interfaces

    private func interfaceRow(_ interface: NetworkInterface) -> some View {
        DisclosureRow(id: "if-\(interface.bsdName)", expanded: $expanded) {
            FleetRowLabel(icon: interface.kind.symbol,
                          tone: interface.tone,
                          title: interface.displayName,
                          subtitle: interfaceSubtitle(interface),
                          inlineSubtitle: true) {
                // Segment membership is an **identity**, not a status, so the
                // tag is `.neutral` and never takes a tone hue: "which segment
                // am I on" has no good/bad axis, and routing it through
                // `StatusTone` would make one VLAN green and another amber for
                // no reason a reader could reconstruct.
                //
                // The label is only ever drawn from something that was told to
                // us — the host's own 802.1Q tag, or a segment a `VLANSource`
                // named. It is never inferred from an address: 10.10.40.0/24
                // looks like VLAN 40 and reading the third octet is right on one
                // network and confidently wrong on the next.
                if let label = vlanLabel(interface) {
                    Tag(text: label, tone: .neutral)
                }
            }
        } detail: {
            VStack(alignment: .leading, spacing: 3) {
                KeyValue(key: "Device", value: interface.bsdName, monospaced: true)
                KeyValue(key: "Status", value: interface.statusLabel)
                ForEach(Array(interface.ipv4.enumerated()), id: \.offset) { index, address in
                    KeyValue(key: index == 0 ? "IPv4" : "IPv4 \(index + 1)",
                             value: address, monospaced: true)
                }
                if let subnet = interface.subnet {
                    KeyValue(key: "Subnet", value: subnet.cidr, monospaced: true)
                }
                // One v6 address, not the six a modern Mac holds: the rest are
                // temporary privacy addresses that rotate, and listing them
                // turns a diagnostic row into a wall.
                if let v6 = interface.routableIPv6.first ?? interface.ipv6.first {
                    KeyValue(key: "IPv6", value: v6, monospaced: true)
                }
                if let mac = interface.macAddress {
                    KeyValue(key: "MAC", value: mac, monospaced: true)
                }
                if let mtu = interface.mtu {
                    KeyValue(key: "MTU", value: "\(mtu)")
                }
                if let tag = interface.vlanTag {
                    KeyValue(key: "VLAN tag", value: "\(tag)")
                    KeyValue(key: "Parent", value: interface.vlanParent ?? "—", monospaced: true)
                }
                if let route = routing.route(forInterface: interface.bsdName) {
                    KeyValue(key: "Default route",
                             value: (route.gateway ?? "link")
                                + (route.isPrimary ? "  (in use)" : "  (not the path in use)"),
                             monospaced: true)
                }
                if let segment = interface.segment {
                    KeyValue(key: "Segment", value: segment.name)
                    if let tag = segment.vlanTag, interface.vlanTag == nil {
                        // Said explicitly, because it is the one number on this
                        // row that did not come off the wire. On an access port
                        // the switch strips the tag; this is a declaration.
                        KeyValue(key: "VLAN tag", value: "\(tag) (not carried on this link)")
                    }
                    if let cidr = segment.cidr {
                        KeyValue(key: "Segment subnet", value: cidr, monospaced: true)
                    }
                    if let purpose = segment.purpose {
                        KeyValue(key: "Purpose", value: purpose)
                    }
                    // Provenance travels with the claim, the same argument
                    // `EvidenceChips` makes about health: a segment on screen
                    // can always be traced to whoever said so.
                    if let source = VLANRegistry.shared.sourceName {
                        KeyValue(key: "Named by", value: source)
                    }
                }
                RowActions {
                    if let address = interface.primaryAddress {
                        Button("Copy address") { actions.copy(address, label: "\(interface.displayName) address") }
                    }
                    if let subnet = interface.subnet {
                        Button("Copy subnet") { actions.copy(subnet.cidr, label: "subnet") }
                    }
                }
            }
        }
    }

    /// The four states, in one place.
    ///
    /// 1. Host has an 802.1Q sub-interface → the tag, read off `ifconfig`.
    ///    Both facts when a source also named it: `VLAN 40 · Guest`.
    /// 2. A source named the segment for an untagged interface → the segment's
    ///    own tag if it declared one, otherwise just the name. This is the
    ///    access-port case, where the switch strips the tag before the frame
    ///    reaches the NIC and the host has no tag of its own to show.
    /// 3. Untagged and unnamed → **nil**. No badge, no placeholder. The subnet
    ///    in the subtitle is the honest artifact and it is already there.
    /// 4. Nothing → nil.
    private func vlanLabel(_ interface: NetworkInterface) -> String? {
        let tag = interface.vlanTag ?? interface.segment?.vlanTag
        switch (tag, interface.segment?.name) {
        case let (.some(tag), .some(name)): return "VLAN \(tag) · \(name)"
        case let (.some(tag), nil): return "VLAN \(tag)"
        case let (nil, .some(name)): return name
        case (nil, nil): return nil
        }
    }

    /// The subtitle competes for width against a `Tag` that pins its own size,
    /// so it is what truncates. Two drafts lost something that mattered — the
    /// first ate the device name, the second ate the word *secondary* — and both
    /// were symptoms of putting four facts in a 380pt row behind an icon.
    ///
    /// The fix is separation rather than abbreviation. **Which interface is the
    /// path in use is the routing row's question**, and the routing row already
    /// answers it twice: its summary names the winning interface, and its
    /// expanded detail lists every default route with the one in use marked.
    /// Restating it on each interface was a third copy competing for the width
    /// that the address needs.
    ///
    /// What is left is what an interface row is for: where it is, and what it is
    /// on. Address and prefix are one token in CIDR form — `10.10.40.12/24`
    /// rather than `10.10.40.12 · /24`, shorter and how anyone would write it —
    /// and `en1` is dropped when a segment name is already carrying the row's
    /// identity, since a BSD device name is the least interesting thing on a row
    /// that says *Guest*. It stays in the expanded detail.
    private func interfaceSubtitle(_ interface: NetworkInterface) -> String {
        var parts: [String] = []
        if let address = interface.primaryAddress {
            parts.append(interface.subnet.map { "\(address)/\($0.prefixLength)" } ?? address)
        } else {
            parts.append(interface.statusLabel)
        }
        if interface.isSelfAssigned { parts.append("no DHCP") }
        if vlanLabel(interface) == nil { parts.append(interface.bsdName) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Segments

    /// Only reachable when `VLANRegistry.shared.isAvailable`.
    private var segmentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CompactHeader(title: "Segments",
                          trailing: VLANRegistry.shared.sourceName)
            ForEach(VLANRegistry.shared.segments) { segment in
                CompactRow(icon: "rectangle.3.group",
                           tone: .neutral,
                           title: segment.name,
                           subtitle: [segment.vlanTag.map { "VLAN \($0)" }, segment.purpose]
                                .compactMap { $0 }.joined(separator: " · "),
                           trailing: segment.cidr ?? "")
            }
        }
    }

    // MARK: - Diagnostic output

    /// The result of the last ping or traceroute, in place.
    ///
    /// Monospaced and scrollable rather than a sheet: the output is columns, and
    /// a popover that opens a window to show four lines of text has lost the
    /// argument for being a popover.
    private func diagnosticOutput(_ outcome: NetworkActions.Outcome) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: outcome.succeeded ? "checkmark.circle" : "xmark.circle")
                    .foregroundStyle(outcome.succeeded ? StatusTone.good.ink : StatusTone.bad.ink)
                Text(outcome.title)
                    .font(FleetFont.micro)
                    .lineLimit(1)
                Spacer(minLength: 0)
                IconButton(symbol: "doc.on.doc", help: "Copy this output") {
                    actions.copy(outcome.output, label: "output")
                }
                IconButton(symbol: "xmark", help: "Dismiss") { actions.clearOutcome() }
            }
            // Both axes, and clipped. `fixedSize` gives the text its full
            // intrinsic height, so a horizontal-only ScrollView never clipped the
            // vertical overflow — `maxHeight` bounded the frame while the content
            // drew straight through it and over the rest of the popover. Four
            // lines of ping never reached the bound; a support bundle is hundreds.
            ScrollView([.horizontal, .vertical]) {
                Text(outcome.output.isEmpty ? "(no output)" : outcome.output)
                    .font(FleetFont.mono(10))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
            }
            .frame(maxHeight: 132)
            .clipped()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FleetColor.surfaceWash,
                    in: RoundedRectangle(cornerRadius: FleetMetrics.tileCorner, style: .continuous))
        .padding(.horizontal, FleetMetrics.rowInset)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(outcome.title), \(outcome.succeeded ? "succeeded" : "failed")")
    }
}

/// The admin rows plus their footer, with the disclosure state owned locally.
///
/// Exists so `SurfaceRenderer` can capture this section on its own — inside the
/// Connections tab it lives below a scroll fold a still capture cannot reach.
/// It is the shipping views, composed, not a second drawing of them.
struct NetworkAdminPreview: View {
    @Bindable var model: AppModel
    @State private var expanded: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NetworkAdminSection(model: model, expanded: $expanded)
            Divider()
            NetworkAdminFooter(model: model)
        }
        .frame(width: FleetMetrics.popoverWidth)
    }
}

// MARK: - Footer

/// The admin-console footer, and the shape the VLAN console will take.
///
/// Two links, one mechanism. `AdminConsole` is an enum rather than a pair of
/// hard-coded buttons precisely so the VLAN case is a `case` and a config key,
/// not a second footer with its own layout: adding it later means giving the
/// enum a third case and giving `Consoles` a third field.
///
/// The network console's URL **resolves** rather than being stored: with nothing
/// in config it is `http://<default gateway>`, which is the router admin page on
/// essentially every home and small-office network, and needs no setup. With no
/// gateway there is no URL, so the button is absent — the capability rule applied
/// to a link.
enum AdminConsole: String, CaseIterable, Identifiable {
    case network
    case vlan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .network: return "Network Console"
        case .vlan: return "VLAN Console"
        }
    }

    var symbol: String {
        switch self {
        case .network: return "network"
        case .vlan: return "rectangle.3.group"
        }
    }

    /// Configured URL first, then whatever the case can derive on its own.
    @MainActor
    func url(settings: Settings, routing: RoutingStatus) -> URL? {
        let configured: String?
        switch self {
        case .network: configured = settings.consoles.network
        case .vlan: configured = settings.consoles.vlan
        }
        if let configured, let url = URL(string: configured) { return url }

        switch self {
        case .network:
            guard let gateway = routing.defaultGatewayIPv4 else { return nil }
            return URL(string: "http://\(gateway)")
        case .vlan:
            // Nothing to derive. A VLAN console is a controller somebody runs;
            // this machine cannot guess its address, so with no config key and
            // no registered source the entry does not render at all.
            return nil
        }
    }

    /// Whether this entry appears. `vlan` additionally requires a registered
    /// source, so a stray config key alone cannot conjure a VLAN section that
    /// has no data behind it.
    @MainActor
    func isAvailable(settings: Settings, routing: RoutingStatus) -> Bool {
        guard url(settings: settings, routing: routing) != nil else { return false }
        switch self {
        case .network: return true
        case .vlan: return VLANRegistry.shared.isAvailable
        }
    }
}

struct NetworkAdminFooter: View {
    @Bindable var model: AppModel

    var body: some View {
        let available = AdminConsole.allCases.filter {
            $0.isAvailable(settings: model.settings, routing: model.network.routing)
        }
        if !available.isEmpty {
            HStack(spacing: 6) {
                ForEach(available) { console in
                    Button {
                        if let url = console.url(settings: model.settings,
                                                 routing: model.network.routing) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label(console.title, systemImage: console.symbol)
                            .font(FleetFont.subtitle)
                    }
                    .buttonStyle(.link)
                    .help(console.url(settings: model.settings, routing: model.network.routing)?
                        .absoluteString ?? console.title)
                }
                Spacer(minLength: 0)
                Button("Support Bundle") { copySupportBundle() }
                    .buttonStyle(.link)
                    .font(FleetFont.subtitle)
                    .help("Copy a sanitised JSON snapshot of the network picture. "
                          + "Public addresses, MACs and the Wi-Fi network name are masked.")
            }
            .padding(.horizontal, FleetMetrics.gutter)
            .padding(.vertical, 7)
        }
    }

    private func copySupportBundle() {
        let json = SupportBundle.json(routing: model.network.routing,
                                      wifi: model.network.wifi,
                                      vpn: model.network.vpn,
                                      vlanSourceName: VLANRegistry.shared.sourceName,
                                      segments: VLANRegistry.shared.segments)
        model.actions.copy(json, label: "support bundle")
    }
}
