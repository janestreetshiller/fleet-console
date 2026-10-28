import SwiftUI
import FleetCore

/// The Network tab: every segment at once, one tile each, no scrolling.
///
/// This tab was the full administration list — internet, three links, routing,
/// resolvers, overlays, local fabric, devices, listeners — as disclosure rows a
/// screen and a half tall inside a 300pt menu. You scrolled to learn whether
/// the VPN was up. Each segment is one tile now, carrying the one reading worth
/// a glance; the rows, their probes and the admin consoles are one click away
/// in Details, which is where reading at length belongs.
struct NetworkGlance: View {
    @Bindable var model: AppModel
    @State private var showingDetails = false

    private var net: NetworkMonitor { model.network }

    var body: some View {
        VStack(spacing: 10) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow { internet; gateway }
                GridRow { ethernet; wifi }
                GridRow { tailscale; dns }
                GridRow { vpn; thunderbolt }
                GridRow { devices; listening }
            }
            HStack(spacing: 8) {
                Text("As of \(Fmt.relative(net.internet.checkedAt))")
                    .font(FleetFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                Spacer(minLength: 8)
                Button("Re-probe") {
                    net.refresh()
                    model.refreshDevices()
                }
                .controlSize(.small)
                Button("Details…") { showingDetails = true }
                    .controlSize(.small)
                    .accessibilityIdentifier("network.details")
            }
        }
        .padding(.horizontal, FleetMetrics.gutter)
        .padding(.vertical, 12)
        .sheet(isPresented: $showingDetails) { NetworkDetailsSheet(model: model) }
    }

    // MARK: Tiles

    private var internet: some View {
        let status = net.internet
        return tile("Internet", symbol: status.reachable == false ? "globe.badge.chevron.backward" : "globe",
                    value: status.summary.capitalizedFirst,
                    tone: status.reachable == true ? .good : status.reachable == false ? .bad : .unknown)
    }

    private var gateway: some View {
        let routing = net.routing
        return tile("Gateway", symbol: "point.3.connected.trianglepath.dotted",
                    value: routing.primaryRoute == nil ? "No default route" : routing.summary,
                    tone: routing.primaryRoute == nil ? .bad : .good)
    }

    private var ethernet: some View {
        let status = net.ethernet
        let value = status.connected
            ? [status.ipv4, status.linkSpeed].compactMap { $0 }.joined(separator: " · ")
            : "Not connected"
        return tile(status.displayName, symbol: "cable.connector",
                    value: value.isEmpty ? "Connected" : value,
                    tone: status.connected ? .good : .neutral)
    }

    private var wifi: some View {
        let status = net.wifi
        let value: String
        if !status.poweredOn { value = "Off" }
        else if !status.connected { value = "Not connected" }
        else { value = [status.ssid, status.rssi.map { "\($0) dBm" }].compactMap { $0 }.joined(separator: " · ") }
        return tile("Wi-Fi", symbol: status.poweredOn ? "wifi" : "wifi.slash",
                    value: value.isEmpty ? "Connected" : value,
                    tone: status.connected ? .good : .neutral)
    }

    private var tailscale: some View {
        let status = net.tailscale
        let value: String
        let tone: StatusTone
        if !status.installed { value = "Not installed"; tone = .neutral }
        else if !status.running { value = status.backendState; tone = .warn }
        else { value = "\(status.onlinePeerCount) of \(status.peerCount) peers online"; tone = .good }
        return tile("Tailscale", symbol: "network", value: value, tone: tone)
    }

    private var dns: some View {
        let resolvers = net.routing.resolvers
        let value = resolvers.isEmpty ? "None configured"
            : resolvers[0] + (resolvers.count > 1 ? " +\(resolvers.count - 1)" : "")
        return tile("DNS", symbol: "text.magnifyingglass", value: value,
                    tone: resolvers.isEmpty ? .warn : .good,
                    help: resolvers.joined(separator: ", "))
    }

    private var vpn: some View {
        let status = net.vpn
        let value: String
        if let connected = status.connectedService { value = connected.name }
        else if status.services.isEmpty { value = "None configured" }
        else { value = "\(status.services.count) configured, off" }
        return tile("VPN", symbol: "lock.shield", value: value,
                    tone: status.connectedService == nil ? .neutral : .good, help: status.summary)
    }

    private var thunderbolt: some View {
        let status = net.thunderbolt
        let value = status.ports.isEmpty ? "No ports"
            : status.activePorts.isEmpty ? "No links" : "\(status.activePorts.count) linked"
        return tile("Thunderbolt", symbol: "bolt.horizontal", value: value,
                    tone: status.activePorts.isEmpty ? .neutral : .good, help: status.summary)
    }

    private var devices: some View {
        let rows = model.deviceRows.filter { !$0.record.evidence.isSelf }
        let reachable = rows.filter { $0.record.health == .reachable }.count
        return tile("Devices", symbol: "desktopcomputer",
                    value: rows.isEmpty ? "None linked" : "\(reachable) of \(rows.count) reachable",
                    tone: rows.isEmpty ? .neutral : reachable == rows.count ? .good : .warn)
    }

    private var listening: some View {
        let count = model.unmanaged.filter { !$0.ports.isEmpty }.count
        return tile("Listening", symbol: "dot.radiowaves.left.and.right",
                    value: count == 0 ? "No unmanaged sockets" : "\(count) unmanaged",
                    tone: count == 0 ? .good : .warn)
    }

    private func tile(_ title: String, symbol: String, value: String, tone: StatusTone,
                      help: String? = nil) -> some View {
        NetworkTile(title: title, symbol: symbol, value: value, tone: tone) { showingDetails = true }
            .help("\(title): \(help ?? value)")
    }
}

/// One segment: what it is and its one reading. The whole tile opens Details.
struct NetworkTile: View {
    let title: String
    let symbol: String
    let value: String
    let tone: StatusTone
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                EntityIcon(symbol: symbol, tone: tone, size: FleetMetrics.iconCompact)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(FleetFont.rowTitleCompact.weight(.medium))
                    Text(value)
                        .font(FleetFont.nano)
                        .foregroundStyle(tone == .bad || tone == .warn ? tone.ink : SurfaceInk.secondary)
                        .truncationMode(.tail)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovering ? FleetColor.surfaceWash : .clear,
                    in: RoundedRectangle(cornerRadius: FleetMetrics.tileCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FleetMetrics.tileCorner, style: .continuous)
                .strokeBorder(ConsoleColor.hairline, lineWidth: 1)
        }
        .onHover { hovering = $0 }
        .accessibilityLabel("\(title), \(value)")
    }
}

/// The full network rows, probes and admin consoles, at reading length.
struct NetworkDetailsSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Network").font(FleetFont.title)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(FleetMetrics.gutter)
            Divider()
            ConnectionsPopover(model: model, openDashboard: {}, embedded: true)
            Divider()
            NetworkAdminFooter(model: model)
        }
        .frame(width: FleetMetrics.popoverWidth, height: 560)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
