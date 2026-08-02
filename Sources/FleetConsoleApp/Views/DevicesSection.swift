import SwiftUI
import FleetCore

struct DevicesSection: View {
    @Bindable var model: AppModel
    @State private var expanded: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Devices") {
                IconButton(symbol: "arrow.clockwise", help: "Re-probe every device") {
                    model.refreshDevices()
                }
            }

            if model.deviceRows.isEmpty {
                Text(model.connected
                     ? "No devices configured — add them in config.json."
                     : "Waiting for the controller…")
                    .font(FleetFont.subtitle)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, FleetMetrics.gutter)
                    .padding(.vertical, 4)
            } else {
                ForEach(model.deviceRows) { row in
                    DeviceRowView(row: row, expanded: $expanded, model: model)
                }
            }
        }
    }
}

struct DeviceRowView: View {
    @Bindable var row: DeviceRow
    @Binding var expanded: String?
    let model: AppModel

    private var device: DeviceRecord { row.record }

    /// Names the probe that produced the verdict. "Online" on its own is the claim
    /// this app will not make.
    private var summary: String {
        let e = device.evidence
        if e.isSelf { return "this machine" }
        switch device.health {
        case .unknown: return "not probed yet"
        case .reachable, .partial:
            var parts: [String] = []
            if e.icmpOK == true { parts.append(e.icmpRTTms.map { String(format: "ping %.0f ms", $0) } ?? "ping ok") }
            else if e.icmpOK == false { parts.append("ping ✕") }
            if e.tcpOK == true { parts.append("tcp :\(e.tcpPort ?? 0) ok") }
            else if e.tcpOK == false { parts.append("tcp ✕") }
            if e.tailscaleOnline == true { parts.append("tailnet online") }
            return parts.joined(separator: " · ")
        case .unreachable:
            return "unreachable · last seen \(Fmt.relative(device.lastReachableAt))"
        }
    }

    var body: some View {
        DisclosureRow(id: device.id, expanded: $expanded,
                      help: "\(device.health.label) — \(device.model.isEmpty ? device.name : device.model)") {
            FleetRowLabel(icon: device.evidence.isSelf ? "desktopcomputer" : "macpro.gen3",
                          tone: device.health.tone,
                          title: device.name,
                          subtitle: summary,
                          inlineSubtitle: true)
        } detail: {
            VStack(alignment: .leading, spacing: 3) {
                KeyValue(key: "Model", value: device.model.isEmpty ? "—" : device.model)
                KeyValue(key: "Local", value: device.localIP ?? device.localHost ?? "—", monospaced: true)
                KeyValue(key: "Tailscale", value: device.tailscaleIP ?? "—", monospaced: true)
                KeyValue(key: "Tailnet name", value: device.tailscaleHost ?? "—", monospaced: true)
                KeyValue(key: "Last seen", value: device.evidence.isSelf ? "now" : Fmt.relative(device.lastReachableAt))
                KeyValue(key: "Probed", value: Fmt.relative(device.evidence.checkedAt))
                if device.metrics.hasAny {
                    KeyValue(key: "Host", value: device.metrics.line, monospaced: true)
                }

                Divider().padding(.vertical, 2)

                RowActions {
                    Button("Re-probe") { model.refreshDevices() }
                    Button("Edit Devices…") { model.openConfigFile() }
                }
            }
        }
    }
}

/// Shared by the device row and the device inspector — one probe, one rendering.
struct ProbeLine: View {
    let title: String
    let state: Bool?
    var detail: String?

    var body: some View {
        HStack(spacing: 6) {
            let tone: StatusTone = state == nil ? .unknown : (state! ? .good : .bad)
            Image(systemName: tone.verdict)
                .font(FleetFont.micro.weight(.bold))
                .foregroundStyle(tone.ink)
                .frame(width: FleetMetrics.verdictColumn)
            Text(title).font(FleetFont.subtitle)
            Text(state == nil ? "not run" : (state! ? "passed" : "failed"))
                .font(FleetFont.subtitle)
                .foregroundStyle(.secondary)
            if let detail {
                Text("· \(detail)").font(FleetFont.subtitle).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(state == nil ? "not run" : (state! ? "passed" : "failed"))")
    }
}
