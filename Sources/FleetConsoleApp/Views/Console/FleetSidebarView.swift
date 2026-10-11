import SwiftUI
import FleetCore

// Column one: the fleet mesh.
//
// "This Mac" is pinned at the top because it is the device every local module
// describes. Below it, the remote nodes with the evidence that matters before
// you trust a number from them: are they reachable *at all*, over which path,
// and at what latency. Reachability, latency and encryption are three separate
// facts and are drawn as three separate affordances — a green dot over a
// relayed 180 ms path is a different machine from a green dot over direct 4 ms.

struct FleetSidebarView: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel
    @State private var managingDevices = false

    var body: some View {
        // One list, not two. This Mac and the remote nodes were previously split
        // across an unlabelled section and a "Fleet" section, which drew a
        // boundary where there is no distinction: they are all machines you own
        // and all of them are the fleet. The local machine leads because it is
        // the one every local module describes, and it is marked as *this* one
        // by its row, not by being fenced off above a header.
        List(selection: navigationSelection) {
            Section("This Mac") {
                ForEach([ConsoleModule.overview, .processes, .storage]) { module in
                    Label(module.rawValue, systemImage: module.symbol)
                        .font(ConsoleFont.rowTitle)
                        .padding(.vertical, 3)
                        .tag("module:" + module.rawValue)
                }
            }
            Section("Background Work") {
                Label("Needs Attention", systemImage: "exclamationmark.circle")
                    .font(ConsoleFont.rowTitle)
                    .padding(.vertical, 3)
                    .tag("attention")
                ForEach([ConsoleModule.services, .events, .plists]) { module in
                    Label(module.rawValue, systemImage: module.symbol)
                        .font(ConsoleFont.rowTitle)
                        .padding(.vertical, 3)
                        .tag("module:" + module.rawValue)
                }
            }
                Section("Devices") {
                ForEach(model.deviceRows.filter { !$0.record.evidence.isSelf }) { row in
                    DeviceNodeRow(record: row.record)
                        .tag("device:" + row.id)
                }
                Button { managingDevices = true } label: {
                    Label("Link a Device…", systemImage: "plus.circle")
                }
                .help("Multi-device add-on: $10/month through Ouros; linking is available in this preview")
                }
        }
        .listStyle(.sidebar)
        // The mesh sits on the page like everything else. Without this the
        // sidebar column paints AppKit's own vibrancy over the field, and the
        // window has one column that is not on the same sheet of paper as the
        // other two.
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            // The signature: the one place the console signs itself. The mark
            // is drawn on its construction circle and the name is set as a
            // plotted legend beside it — the same treatment every plate label
            // in the app wears, at the one place it is the app's own name.
            HStack(spacing: 8) {
                FleetMark(size: 20)
                Text("FleetConsole")
                    .font(ConsoleFont.cardTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }
        // The column width is set by `ConsoleRootView`, not here: the resting
        // width is the golden section of whatever the split view has to divide,
        // which is a function of the window and of whether a tool panel is open.
        // This view cannot see either, and the number it used to declare was the
        // half of the mirror that drifted — 236/268/320 against the inspector's
        // 280/320/420.
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
        .onAppear { model.refreshDevices() }
        .sheet(isPresented: $managingDevices) { DeviceManagementView(model: model) }
    }

    private var navigationSelection: Binding<String> {
        Binding {
            if !console.isLocalDeviceSelected { return "device:" + console.selectedDeviceID }
            return console.atHome ? "attention" : "module:" + console.module.rawValue
        } set: { destination in
            if destination == "attention" {
                console.goHome()
            } else if destination.hasPrefix("module:"),
                      let module = ConsoleModule(rawValue: String(destination.dropFirst(7))) {
                console.open(module)
            } else if destination.hasPrefix("device:") {
                console.selectedDeviceID = String(destination.dropFirst(7))
                console.atHome = false
            }
        }
    }

    /// Controller state and the local network summary, pinned under the list.
    /// The sidebar is the one column that is always visible, so the two facts
    /// that colour everything else live at its foot.
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            HStack(spacing: 6) {
                StatusPip(tone: model.connected ? .good : .bad, size: 7)
                Text(model.connected ? "Controller connected" : "Controller offline")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(.secondary)
            }
            if let snapshot = model.lastSnapshotAt {
                Text("Updated \(Fmt.relative(snapshot))")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
            }
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(model.network.internet.reachable == false
                                     ? StatusTone.bad.ink : Color.secondary)
                Text(model.network.internet.reachable == false
                     ? "Internet unreachable" : "Internet · \(model.network.internet.summary)")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 0)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Remote node

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
            // The badge, not just the tint. `detailLine` states the *path* to a
            // node — "tailnet · ssh :22" — and never its health, so in the one
            // column that is always on screen, reachability used to live in the
            // pip's hue and nowhere else. Desaturate the sidebar and all four
            // health states looked identical. The badge carries a verdict glyph,
            // and appears only when something is off, so a reachable node stays
            // clean.
            EntityIcon(symbol: symbol,
                       tone: record.health.tone,
                       size: FleetMetrics.iconRowLarge,
                       badge: record.health == .reachable ? nil : record.health.tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .font(ConsoleFont.rowTitle.weight(.medium))
                    .lineLimit(1)
                Text(detailLine)
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                StatusPip(tone: record.health.tone, size: 7,
                          pulsing: record.health == .reachable)
                if let rtt = record.evidence.icmpRTTms, record.health != .unreachable {
                    ConsoleBadge(text: ConsoleFmt.latency(rtt), tone: latencyTone)
                }
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

    /// Path and encryption as one glanceable line: the transport (Tailscale or
    /// LAN) and the probe channel (SSH). A node you reach through an encrypted
    /// mesh over SSH reads differently from a bare LAN ping, and should.
    /// The model name is deliberately absent. This line exists to say *how the
    /// node is reached* — the transport and the probe channel — and the sidebar
    /// gives it about 130pt. With the model in front, "Intel · tailnet · ssh :22"
    /// overran that and truncated to "Intel · t… · ssh :22", destroying the one
    /// token the line is for. The machine is already identified twice above it,
    /// by the row's name and by its icon, and the full model is in the inspector.
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
