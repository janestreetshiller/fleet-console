import SwiftUI
import AppKit
import FleetCore

/// Item 1 — Connections. Everything about how this machine is attached to
/// anything else: internet, LAN, Tailscale, VPN, VLAN, Thunderbolt, exo.
///
/// Rows that are not configured say so rather than being hidden: "no VLANs
/// configured" is an answer, and hiding it would leave you wondering whether the
/// app checked at all.
struct ConnectionsPopover: View {
    @Bindable var model: AppModel
    var openDashboard: () -> Void

    @State private var expanded: String?

    private var net: NetworkMonitor { model.network }

    /// `true` when this view is shown inside Fleet's unified popover rather than
    /// owning a second status item and its own chrome.
    var embedded = false

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                VStack(spacing: 0) {
                    header
                    Divider()
                    content
                    Divider()
                    NetworkAdminFooter(model: model)
                    Divider()
                    PopoverFooter(model: model, openDashboard: openDashboard)
                }
                .frame(width: FleetMetrics.popoverWidth)
            }
        }
    }

    private var header: some View {
        PopoverHeader(title: "Connections", symbol: "antenna.radiowaves.left.and.right") {
            IconButton(symbol: "arrow.clockwise", help: "Re-probe everything") {
                net.refresh()
                model.refreshDevices()
            }
            IconButton(symbol: "gearshape", help: "Open Network settings") {
                net.openSettings(.network)
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.settings.sections.listening { listeningSection }

                CompactHeader(title: "Internet & LAN")
                internetRow
                NetworkSection(model: model)

                // Routing, resolvers and the interface inventory — the
                // administration layer. It sits under the link rows because the
                // order is the order you ask the questions in: am I attached,
                // then where do my packets go.
                NetworkAdminSection(model: model, expanded: $expanded)

                OverlaySection(model: model, expanded: $expanded)

                CompactHeader(title: "Local fabric")
                thunderboltRow
                exoRow

                if model.settings.sections.devices { DevicesSection(model: model) }
                Spacer(minLength: 6)
            }
        }
        .frame(maxHeight: FleetMetrics.sectionMaxHeight)
    }

    /// What on this machine is actually holding a socket.
    ///
    /// This tab opened on four `StatTile`s — Internet, Link, Tailnet, Devices —
    /// and every one of those facts is restated, with its evidence, in the rows
    /// immediately below: the Internet row says "reachable · 6 ms", the Tailscale
    /// row gives the tailnet IP, Devices has its own section. So the tiles were
    /// a second, thinner copy of the page under them.
    ///
    /// What was missing is the thing a network surface is opened *for*: which
    /// processes are listening, on what. The controller already knows —
    /// `activeServices` carries the ports it verified, and `unmanaged` is
    /// everything holding a socket it did not launch. Those two together are the
    /// listening set, and the split between them is the interesting part.
    private var listeningSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CompactHeader(title: "Listening",
                          trailing: listenerCount == 0 ? nil : "\(listenerCount)")

            if listenerCount == 0 {
                EmptyLine(text: model.connected
                          ? "nothing unmanaged is holding a listening socket"
                          : "controller unavailable")
            } else {
                ForEach(listeningUnmanaged, id: \.id) { process in
                    CompactRow(icon: "questionmark.circle",
                               tone: .warn,
                               title: process.command,
                               subtitle: "unmanaged · pid \(process.pid) · \(process.user)",
                               trailing: portList(process.ports))
                }
            }
        }
    }

    /// Observed sockets only — `evidence.listeningPorts`, not `effectivePorts`,
    /// which falls back to what a service *declared*. A section titled
    /// "Listening" that lists a port nobody has seen listening would be exactly
    /// the kind of claim the rest of this app refuses to make.
    /// Unmanaged listeners only.
    ///
    /// This section used to list managed services too, on the argument that a
    /// network surface is opened to find out what is holding a socket. The
    /// argument is sound and the result was not: a managed service already has a
    /// row on the Services tab with its state, its owner, its lease and its verbs,
    /// so listing it again here made every managed service appear on two tabs and
    /// left neither one authoritative. Services live on Services. What this tab
    /// adds is the half the controller does not own — the sockets held by things
    /// it never launched.
    private var listeningUnmanaged: [UnmanagedProcess] {
        model.unmanaged.filter { !$0.ports.isEmpty }
    }

    private var listenerCount: Int { listeningUnmanaged.count }

    /// Two ports fit the trailing column at this width; past that the count
    /// carries it rather than a list that would truncate mid-number.
    private func portList(_ ports: [Int]) -> String {
        let sorted = ports.sorted()
        if sorted.count <= 2 { return sorted.map { ":\($0)" }.joined(separator: " ") }
        return ":\(sorted[0]) +\(sorted.count - 1)"
    }

    // MARK: - Rows

    private var internetRow: some View {
        let status = net.internet
        return DisclosureRow(id: "internet", expanded: $expanded) {
            FleetRowLabel(icon: status.reachable == true ? "globe" : "globe.badge.chevron.backward",
                          tone: status.reachable == true ? .good : (status.reachable == nil ? .unknown : .bad),
                          title: "Internet",
                          subtitle: status.summary,
                          inlineSubtitle: true)
        } detail: {
            VStack(alignment: .leading, spacing: 3) {
                RowActions {
                    Button("Re-probe") { net.refresh() }
                }
            }
        }
    }

    private var thunderboltRow: some View {
        let status = net.thunderbolt
        return DisclosureRow(id: "thunderbolt", expanded: $expanded) {
            FleetRowLabel(icon: "bolt.horizontal.fill",
                          tone: status.activePorts.isEmpty ? .neutral : .good,
                          title: "Thunderbolt",
                          subtitle: status.summary,
                          inlineSubtitle: true)
        } detail: {
            VStack(alignment: .leading, spacing: 3) {
                if status.ports.isEmpty {
                    KeyValue(key: "Ports", value: "0")
                } else {
                    ForEach(status.ports) { port in
                        KeyValue(key: port.name,
                                 value: "\(port.device) · \(port.active ? "linked" : "no link")"
                                    + (port.ipv4.map { " · \($0)" } ?? ""),
                                 monospaced: true)
                    }
                }
                KeyValue(key: "Checked", value: Fmt.relative(status.checkedAt))
            }
        }
    }

    private var exoRow: some View {
        let status = net.exo
        return DisclosureRow(id: "exo", expanded: $expanded) {
            FleetRowLabel(icon: "cpu",
                          tone: status.tone,
                          title: "exo",
                          subtitle: status.summary,
                          inlineSubtitle: true)
        } detail: {
            VStack(alignment: .leading, spacing: 3) {
                KeyValue(key: "Binary", value: status.executablePath ?? "not on PATH", monospaced: true)
                KeyValue(key: "Processes", value: "\(status.processCount)")
                KeyValue(key: "Endpoint", value: status.endpoint, monospaced: true)
                KeyValue(key: "Endpoint answers",
                         value: status.endpointReachable == nil ? "not checked"
                              : (status.endpointReachable! ? "yes" : "no"))
                KeyValue(key: "Checked", value: Fmt.relative(status.checkedAt))
                RowActions { Button("Re-probe") { net.refresh() } }
            }
        }
    }

    // MARK: - Tile values

    private var linkValue: String {
        if net.ethernet.connected { return "wired" }
        if net.wifi.connected { return "Wi-Fi" }
        return "down"
    }

    private var linkTone: StatusTone {
        (net.ethernet.connected || net.wifi.connected) ? .good : .bad
    }

    private var reachableDevices: String {
        let total = model.deviceRows.count
        guard total > 0 else { return "—" }
        return "\(model.deviceRows.filter { $0.record.health == .reachable }.count)/\(total)"
    }

    private var deviceTone: StatusTone {
        guard !model.deviceRows.isEmpty else { return .neutral }
        if model.deviceRows.contains(where: { $0.record.health == .unreachable }) { return .warn }
        if model.deviceRows.allSatisfy({ $0.record.health == .reachable }) { return .good }
        return .neutral
    }
}

// MARK: - Overlays

/// VPN and VLAN — the two things layered *over* the link rather than carried by
/// it. Its own view, like `NetworkSection` and `NetworkAdminSection`, so the
/// design sheet can capture it: inside the tab these rows sit below the
/// `FleetMetrics.sectionMaxHeight` scroll clamp that a still capture cannot reach, and a
/// surface the sheet cannot show is a surface nobody reviews. That is not
/// hypothetical — the VLAN row shipped reading "none on this Mac" directly under
/// a Segments list naming four VLANs, and it took a screenshot from the running
/// app to catch it.
struct OverlaySection: View {
    @Bindable var model: AppModel
    @Binding var expanded: String?

    private var net: NetworkMonitor { model.network }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CompactHeader(title: "Overlays")
            vpnRow
            vlanRow
        }
    }

    private var vpnRow: some View {
        let status = net.vpn
        let others = status.tunnels.filter { !$0.isTailscale }
        return DisclosureRow(id: "vpn", expanded: $expanded) {
            FleetRowLabel(icon: status.connectedService != nil ? "lock.shield.fill" : "lock.shield",
                          tone: status.connectedService != nil ? .good : .neutral,
                          title: "VPN",
                          subtitle: status.summary,
                          inlineSubtitle: true)
        } detail: {
            VStack(alignment: .leading, spacing: 3) {
                KeyValue(key: "Configured", value: "\(status.services.count)")
                ForEach(status.services) { service in
                    KeyValue(key: service.name,
                             value: "\(service.state)\(service.enabled ? "" : " · disabled")")
                }
                Divider().padding(.vertical, 2)
                Text("Tunnel interfaces").font(FleetFont.micro).foregroundStyle(.tertiary)
                KeyValue(key: "Up", value: "\(status.tunnels.count)")
                ForEach(status.tunnels) { tunnel in
                    KeyValue(key: tunnel.interface,
                             value: (tunnel.ipv4 ?? "no address")
                                + (tunnel.isTailscale ? "  (Tailscale)" : ""),
                             monospaced: true)
                }
                KeyValue(key: "Non-Tailscale", value: "\(others.count)")
                KeyValue(key: "Checked", value: Fmt.relative(status.checkedAt))
                RowActions {
                    Button("Open VPN Settings") { net.openSettings(.network) }
                }
            }
        }
    }

    /// Two sources answer VLAN questions and they answer *different* ones, so
    /// this row has to say which it is answering or it contradicts the Segments
    /// list a few rows above it.
    ///
    /// It shipped as "none on this Mac" while Segments listed four VLANs read
    /// from `config.json`. Both statements were true — this host has no 802.1Q
    /// sub-interface, *and* it sits on VLAN 40 through an untagged access port —
    /// but put one under the other with no reconciliation and the surface reads
    /// as broken. "None" was also doing too much work: the question is not
    /// whether VLANs exist, it is whether **this Mac carries tags itself**.
    ///
    /// So the subtitle leads with membership when a segment matched, and the
    /// local-trunk answer moves into the detail where it belongs.
    private var vlanRow: some View {
        let status = net.vlan
        let membership = segmentMemberships
        return DisclosureRow(id: "vlan", expanded: $expanded) {
            FleetRowLabel(icon: "rectangle.3.group",
                          tone: !status.interfaces.isEmpty || !membership.isEmpty ? .good : .unknown,
                          title: "VLAN",
                          subtitle: vlanSummary(status: status, membership: membership),
                          inlineSubtitle: true)
        } detail: {
            VStack(alignment: .leading, spacing: 3) {
                // What this host is *on*, which is the thing you actually want,
                // and which no amount of looking at `ifconfig` will tell you.
                if membership.isEmpty {
                    KeyValue(key: "Segment", value: "no interface matched a declared segment")
                } else {
                    ForEach(membership, id: \.interface) { entry in
                        KeyValue(key: entry.interface,
                                 value: entry.label + " · untagged access port")
                    }
                    if let source = VLANRegistry.shared.sourceName {
                        KeyValue(key: "Named by", value: source)
                    }
                }
                Divider().padding(.vertical, 2)
                // What this host *carries*, which is a separate fact and the one
                // the local probe can actually establish.
                KeyValue(key: "802.1Q on host", value: status.interfaces.isEmpty
                         ? "none — no tagged sub-interface"
                         : status.interfaces.joined(separator: ", "),
                         monospaced: !status.interfaces.isEmpty)
                KeyValue(key: "Source", value: "networksetup -listVLANs", monospaced: true)
                KeyValue(key: "Checked", value: Fmt.relative(status.checkedAt))
                RowActions { Button("Open Network Settings") { net.openSettings(.network) } }
            }
        }
    }

    /// Which of this host's interfaces landed on a declared segment.
    private var segmentMemberships: [(interface: String, label: String)] {
        net.routing.interfaces.compactMap { interface in
            guard interface.isInteresting, let segment = interface.segment else { return nil }
            let label = segment.vlanTag.map { "VLAN \($0) · \(segment.name)" } ?? segment.name
            return (interface.displayName, label)
        }
    }

    private func vlanSummary(status: VLANStatus,
                             membership: [(interface: String, label: String)]) -> String {
        if let first = membership.first {
            let extra = membership.count - 1
            return extra > 0 ? "\(first.label) +\(extra)" : first.label
        }
        if !status.interfaces.isEmpty { return status.summary }
        // No segment source and no local tag: say what was checked, not "none".
        return "no 802.1Q interface on this Mac"
    }

}

/// `OverlaySection` with its disclosure state owned locally, so the design sheet
/// can capture it on its own.
struct OverlaysPreview: View {
    @Bindable var model: AppModel
    @State private var expanded: String?

    var body: some View {
        OverlaySection(model: model, expanded: $expanded)
            .frame(width: FleetMetrics.popoverWidth)
    }
}
