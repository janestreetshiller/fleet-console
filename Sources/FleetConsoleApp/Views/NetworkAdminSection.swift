import SwiftUI
import AppKit
import FleetCore

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

    private func isMagicDNS(_ server: String) -> Bool {
        server == "100.100.100.100" || server.lowercased().hasPrefix("fd7a:115c:a1e0:")
    }

    private func interfaceRow(_ interface: NetworkInterface) -> some View {
        DisclosureRow(id: "if-\(interface.bsdName)", expanded: $expanded) {
            FleetRowLabel(icon: interface.kind.symbol,
                          tone: interface.tone,
                          title: interface.displayName,
                          subtitle: interfaceSubtitle(interface),
                          inlineSubtitle: true) {
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
                        KeyValue(key: "VLAN tag", value: "\(tag) (not carried on this link)")
                    }
                    if let cidr = segment.cidr {
                        KeyValue(key: "Segment subnet", value: cidr, monospaced: true)
                    }
                    if let purpose = segment.purpose {
                        KeyValue(key: "Purpose", value: purpose)
                    }
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

    private func vlanLabel(_ interface: NetworkInterface) -> String? {
        let tag = interface.vlanTag ?? interface.segment?.vlanTag
        switch (tag, interface.segment?.name) {
        case let (.some(tag), .some(name)): return "VLAN \(tag) · \(name)"
        case let (.some(tag), nil): return "VLAN \(tag)"
        case let (nil, .some(name)): return name
        case (nil, nil): return nil
        }
    }

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
            return nil
        }
    }

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
