import SwiftUI
import FleetCore

struct FleetSidebarView: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel
    @State private var managingDevices = false

    var body: some View {
        List(selection: navigationSelection) {
            Section {
                Label("Needs Attention", systemImage: "exclamationmark.circle")
                    .tag("attention")
                ForEach([ConsoleModule.overview, .processes, .services]) { module in
                    Label(module.title, systemImage: module.symbol)
                        .accessibilityIdentifier(module == .overview ? "sidebar.awareness" : "sidebar." + module.rawValue)
                        .tag("module:" + module.rawValue)
                }
            }
            Section {
                Label("Agents & Map", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag("agents")
            }
            Section("Devices") {
                ForEach(model.deviceRows.filter { !$0.record.evidence.isSelf }) { row in
                    DeviceNodeRow(record: row.record)
                        .tag("device:" + row.id)
                }
                Button { managingDevices = true } label: {
                    Label("Link a Device…", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(SurfaceInk.secondary)
                .help("Multi-device access: $10/month through Ouros")
            }
        }
        .font(ConsoleFont.rowTitle)
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { profileCard }

        .onAppear { model.refreshDevices() }
        .sheet(isPresented: $managingDevices) { DeviceManagementView(model: model) }
    }

    private var profileCard: some View {
        OurosProfileCard(title: "FleetConsole", detail: accountLine,
                         tone: model.connected ? nil : .bad) {
            FleetBadgeMark(size: $0)
        } menuItems: {
            Button("Ouros Account…") { managingDevices = true }
            Button("Edit Configuration…") { model.openConfigFile() }
            Divider()
            Button("Ouros Website") { model.openURL("https://ouros.md") }
            Button("Source & Support") { model.openURL("https://github.com/janestreetshiller/fleet-console") }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private var accountLine: String {
        guard model.connected else { return "Controller offline" }
        if model.ourosBilling.active { return "Ouros · Multi-device" }
        return model.ourosBilling.signedIn ? "Ouros account" : "Local · Free"
    }

    private var navigationSelection: Binding<String> {
        Binding {
            if !console.isLocalDeviceSelected { return "device:" + console.selectedDeviceID }
            if !console.atHome && console.module == .services && console.operationsSection == "Agents" { return "agents" }
            return console.atHome ? "attention" : "module:" + ([ConsoleModule.storage, .events, .plists].contains(console.module) ? ConsoleModule.services.rawValue : console.module.rawValue)
        } set: { destination in
            if destination == "agents" {
                console.openOperationsSection("Agents")
            } else if destination == "attention" {
                console.goHome()
            } else if destination.hasPrefix("module:"),
                      let module = ConsoleModule(rawValue: String(destination.dropFirst(7))) {
                if module == .services { console.openOperationsSection("Services") }
                else { console.open(module) }
            } else if destination.hasPrefix("device:") {
                console.selectedDeviceID = String(destination.dropFirst(7))
                console.atHome = false
            }
        }
    }


}

private struct DeviceNodeRow: View {
    let record: DeviceRecord

    private var latencyTone: StatusTone {
        guard let rtt = record.evidence.icmpRTTms else { return .neutral }
        switch rtt {
        case ..<20: return .good
        case ..<80: return .warn
        default: return .bad
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            EntityIcon(symbol: symbol,
                       tone: record.health.tone,
                       size: FleetMetrics.iconRowLarge,
                       badge: record.health == .reachable ? nil : record.health.tone)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(record.name)
                        .font(ConsoleFont.rowTitle.weight(.medium))
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    if let rtt = record.evidence.icmpRTTms, record.health != .unreachable {
                        ConsoleBadge(text: ConsoleFmt.latency(rtt), tone: latencyTone)
                            .fixedSize()
                    }
                }
                Text(detailLine)
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .help("\(record.name) · \(record.health.label) · \(detailLine)")
        .accessibilityLabel("\(record.name), \(record.health.label)"
                            + (record.evidence.icmpRTTms.map { ", \(ConsoleFmt.latency($0))" } ?? ""))
    }

    private var symbol: String {
        let model = record.model.lowercased()
        if model.contains("mac mini") { return "macmini.fill" }
        if model.contains("mac studio") { return "macstudio.fill" }
        if model.contains("macbook") { return "laptopcomputer" }
        if model.contains("mac pro") { return "macpro.gen3.fill" }
        return "desktopcomputer"
    }

    private var detailLine: String {
        var parts: [String] = []
        if record.tailscaleIP != nil {
            parts.append("tailnet")
        } else if record.localIP != nil || record.localHost != nil {
            parts.append("LAN")
        }
        if let port = record.probePort {
            parts.append("TCP :\(port)")
        }
        return parts.isEmpty ? "no route configured" : parts.joined(separator: " · ")
    }
}
