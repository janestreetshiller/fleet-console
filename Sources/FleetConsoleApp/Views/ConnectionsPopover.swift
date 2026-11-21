import SwiftUI
import AppKit
import FleetCore

struct ConnectionsPopover: View {
    @Bindable var model: AppModel
    var openDashboard: () -> Void

    @State private var expanded: String?

    private var net: NetworkMonitor { model.network }

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
                internetRow
                NetworkSection(model: model)

                NetworkAdminSection(model: model, expanded: $expanded)

                OverlaySection(model: model, expanded: $expanded)

                CompactHeader(title: "Local fabric")
                thunderboltRow
                exoRow

                if model.settings.sections.devices { DevicesSection(model: model) }
                if model.settings.sections.listening {
                    DisclosureGroup("Listening processes (\(listeningUnmanaged.count))") {
                        listeningSection
                    }
                    .font(FleetFont.body)
                    .padding(.horizontal, FleetMetrics.gutter)
                    .padding(.vertical, 10)
                }
                Spacer(minLength: 6)
            }
        }
        .frame(maxHeight: FleetMetrics.sectionMaxHeight)
    }

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

    private var listeningUnmanaged: [UnmanagedProcess] {
        model.unmanaged.filter { !$0.ports.isEmpty }
    }

    private var listenerCount: Int { listeningUnmanaged.count }

    private func portList(_ ports: [Int]) -> String {
        let sorted = ports.sorted()
        if sorted.count <= 2 { return sorted.map { ":\($0)" }.joined(separator: " ") }
        return ":\(sorted[0]) +\(sorted.count - 1)"
    }

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
                Text("Tunnel interfaces").font(FleetFont.micro).foregroundStyle(SurfaceInk.secondary)
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
        return "no 802.1Q interface on this Mac"
    }

}

struct OverlaysPreview: View {
    @Bindable var model: AppModel
    @State private var expanded: String?

    var body: some View {
        OverlaySection(model: model, expanded: $expanded)
            .frame(width: FleetMetrics.popoverWidth)
    }
}
