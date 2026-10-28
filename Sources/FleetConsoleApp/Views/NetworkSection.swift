import SwiftUI
import AppKit
import FleetCore

/// Network rows, built on the shared FleetKit primitives so an interface row and
/// a service row are recognisably the same kind of object.
struct NetworkSection: View {
    @Bindable var model: AppModel
    @State private var expanded: String?

    private var network: NetworkMonitor { model.network }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ethernetRow
            wifiRow
            tailscaleRow
        }
    }

    // MARK: - Ethernet

    private var ethernetRow: some View {
        let status = network.ethernet
        return DisclosureRow(id: "ethernet", expanded: $expanded) {
            FleetRowLabel(icon: "cable.connector",
                          tone: status.connected ? .good : .neutral,
                          title: status.displayName,
                          subtitle: status.connected
                            ? [status.ipv4, status.linkSpeed].compactMap { $0 }.joined(separator: " · ")
                            : (status.interface == nil ? "no wired interface" : "not connected"),
                          inlineSubtitle: true)
        } detail: {
            VStack(alignment: .leading, spacing: 3) {
                KeyValue(key: "Interface", value: status.interface ?? "—", monospaced: true)
                KeyValue(key: "IPv4", value: status.ipv4 ?? "not assigned", monospaced: true)
                KeyValue(key: "Link speed", value: status.linkSpeed ?? "unavailable")
                KeyValue(key: "Duplex", value: status.duplex ?? "unknown")
                KeyValue(key: "Checked", value: Fmt.relative(status.checkedAt))
                RowActions {
                    Button("Refresh") { network.refreshEthernetOnly() }
                    Button("Open System Settings") { network.openSettings(.network) }
                }
            }
        }
    }

    // MARK: - Wi-Fi

    private var wifiRow: some View {
        let status = network.wifi
        let summary: String
        if !status.poweredOn {
            summary = "Wi-Fi off"
        } else if status.connected {
            let name = status.ssid ?? (status.ssidRequiresLocation ? "network name unavailable" : "connected")
            summary = [name, status.ipv4].compactMap { $0 }.joined(separator: " · ")
        } else {
            summary = "not connected"
        }

        return DisclosureRow(id: "wifi", expanded: $expanded) {
            FleetRowLabel(icon: status.connected ? "wifi" : "wifi.slash",
                          tone: status.connected ? .good : .neutral,
                          title: "Wi-Fi",
                          subtitle: summary,
                          inlineSubtitle: true) {
                if let bars = status.bars {
                    SignalBars(level: bars)
                }
            }
        } detail: {
            VStack(alignment: .leading, spacing: 3) {
                KeyValue(key: "Interface", value: status.interface ?? "—", monospaced: true)
                KeyValue(key: "Network", value: status.ssid ?? (status.ssidRequiresLocation ? "Location permission required" : "—"))
                KeyValue(key: "Signal", value: status.signalDescription)
                if let noise = status.noise {
                    KeyValue(key: "Noise", value: "\(noise) dBm")
                }
                KeyValue(key: "Tx rate", value: status.transmitRateMbps.map { String(format: "%.0f Mbps", $0) } ?? "—")
                KeyValue(key: "Channel", value: status.channel ?? "—")
                KeyValue(key: "IPv4", value: status.ipv4 ?? "not assigned", monospaced: true)

                if status.ssidRequiresLocation {
                    RowActions {
                        Button("Allow Location") { network.requestLocationForSSID() }
                        Button("Privacy Settings") { network.openSettings(.location) }
                    }
                }

                RowActions {
                    Button("Refresh") { network.refresh() }
                    Button("Open Wi-Fi Settings") { network.openSettings(.wifi) }
                }
            }
        }
    }

    // MARK: - Tailscale

    private var tailscaleRow: some View {
        let status = network.tailscale
        let summary: String
        if !status.installed {
            summary = "not installed"
        } else if status.running {
            summary = [status.deviceName, status.ipv4].compactMap { $0 }.joined(separator: " · ")
        } else {
            summary = status.error ?? status.backendState.lowercased()
        }

        return DisclosureRow(id: "tailscale", expanded: $expanded) {
            FleetRowLabel(icon: "point.3.filled.connected.trianglepath.dotted",
                          tone: status.running ? .good : (status.installed ? .warn : .unknown),
                          title: "Tailscale",
                          subtitle: summary,
                          inlineSubtitle: true) {
                if status.exitNodeName != nil {
                    Tag(text: "Exit node", tone: .warn)
                }
            }
        } detail: {
            VStack(alignment: .leading, spacing: 3) {
                KeyValue(key: "State", value: status.backendState)
                KeyValue(key: "This device", value: status.deviceName ?? "—")
                KeyValue(key: "DNS name", value: status.dnsName ?? "—", monospaced: true)
                KeyValue(key: "Tailnet IP", value: status.ipv4 ?? "—", monospaced: true)
                if let tailnet = status.tailnet {
                    KeyValue(key: "Tailnet", value: tailnet)
                }
                KeyValue(key: "Exit node",
                         value: status.exitNodeName.map { "routing through \($0)" }
                            ?? "not in use\(status.offersExitNode ? " · this device offers one" : "")")
                KeyValue(key: "Peers", value: "\(status.onlinePeerCount) online of \(status.peerCount)")
                if let error = status.error {
                    Text(error)
                        .font(FleetFont.caption)
                        .foregroundStyle(StatusTone.warn.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                RowActions {
                    Button("Refresh") { network.refreshTailscaleOnly() }
                    Button("Open Tailscale") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Tailscale.app"))
                    }
                }
            }
        }
    }
}

struct SignalBars: View {
    let level: Int   // 0…4

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(1...4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(bar <= level ? FleetColor.indicatorOn : FleetColor.indicatorOff)
                    .frame(width: 2.5, height: CGFloat(bar) * 2.5 + 2)
            }
        }
        .accessibilityLabel("Signal strength \(level) of 4")
    }
}
