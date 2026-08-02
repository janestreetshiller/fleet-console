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

    var body: some View {
        // One list, not two. This Mac and the remote nodes were previously split
        // across an unlabelled section and a "Fleet" section, which drew a
        // boundary where there is no distinction: they are all machines you own
        // and all of them are the fleet. The local machine leads because it is
        // the one every local module describes, and it is marked as *this* one
        // by its row, not by being fenced off above a header.
        List(selection: $console.selectedDeviceID) {
            Section("Fleet") {
                ThisMacRow(model: model)
                    .tag("self")

                ForEach(model.deviceRows.filter { !$0.record.evidence.isSelf }) { row in
                    DeviceNodeRow(record: row.record)
                        .tag(row.id)
                }
            }
        }
        .listStyle(.sidebar)
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
                Spacer()
                if let snapshot = model.lastSnapshotAt {
                    Text(Fmt.relative(snapshot))
                        .font(ConsoleFont.mono(.caption2))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: model.network.internet.reachable == false
                      ? "wifi.exclamationmark" : "wifi")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(model.network.internet.reachable == false
                                     ? StatusTone.bad.ink : Color.secondary)
                Text(model.network.internet.reachable == false
                     ? "Internet unreachable" : model.network.internet.summary)
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

// MARK: - This Mac

private struct ThisMacRow: View {
    let model: AppModel

    private var cpuTone: StatusTone {
        model.system.cpu.sampled ? SystemThresholds.utilization(model.system.cpu.usage) : .unknown
    }

    var body: some View {
        HStack(spacing: 10) {
            EntityIcon(symbol: "laptopcomputer", tone: cpuTone, size: FleetMetrics.iconRowLarge)
            VStack(alignment: .leading, spacing: 2) {
                Text("This Mac")
                    .font(ConsoleFont.rowTitle.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(ConsoleFont.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            let attention = model.criticalCount + model.warningCount
            if attention > 0 {
                ConsoleBadge(text: "\(attention)",
                             tone: model.criticalCount > 0 ? .bad : .warn,
                             symbol: "exclamationmark.triangle.fill")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard model.system.cpu.sampled else { return model.system.topology.brand }
        return ConsoleFmt.utilPercent(model.system.cpu.usage) + " CPU · "
            + ConsoleFmt.utilPercent(model.system.memory.usedShare) + " RAM"
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
                    .foregroundStyle(.tertiary)
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
            parts.append("ssh :\(port)")
        }
        return parts.isEmpty ? "no route configured" : parts.joined(separator: " · ")
    }
}
