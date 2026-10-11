import SwiftUI
import FleetCore

// Column two for a remote node: what the machine *is*, proven by probes.
//
// FleetConsole never controls a remote process — it reports one. Everything on
// this screen is read-only evidence: the capability probe (SSH, fixed argv,
// BatchMode so a password prompt fails instead of hanging), the link probe
// (`tailscale ping`, worst sample not the mean), and the services that node's
// own controller manages, fetched read-only.

struct DeviceDetailView: View {
    @Bindable var model: AppModel
    let deviceID: String

    private var record: DeviceRecord? {
        model.deviceRows.first { $0.id == deviceID }?.record
    }

    private var capabilities: HostCapabilities? {
        model.hosts.hosts.first { $0.id == deviceID }
    }

    var body: some View {
        ScrollView {
            if let record {
                VStack(alignment: .leading, spacing: 16) {
                    ModuleHeader(
                        title: record.name,
                        subtitle: record.model.isEmpty ? nil : record.model,
                        symbol: "desktopcomputer"
                    ) {
                        StatusPip(tone: record.health.tone, size: 9,
                                  pulsing: record.health == .reachable)
                    }

                    healthCard(record)
                    if let capabilities { capabilityCard(capabilities) }
                    if !record.remoteServices.isEmpty { servicesCard(record) }
                    if let error = record.remoteError { errorCard(error) }
                }
                .padding(ConsoleMetrics.gutter)
            } else {
                ContentUnavailableView("Device not found",
                                       systemImage: "desktopcomputer.trianglebadge.exclamationmark")
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear { probe() }
    }

    private func probe() {
        model.hosts.probe(devices: model.deviceRows.map(\.record))
        model.refreshDevices()
    }

    // MARK: Health evidence

    private func healthCard(_ record: DeviceRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reachability Evidence")
                .font(ConsoleFont.cardTitle)

            EvidenceLine(
                label: "ICMP ping",
                state: record.evidence.icmpOK,
                detail: record.evidence.icmpRTTms.map { ConsoleFmt.latency($0) })
            EvidenceLine(
                label: "TCP probe",
                state: record.evidence.tcpOK,
                detail: record.evidence.tcpPort.map { "port \($0)" })
            EvidenceLine(
                label: "Tailscale",
                state: record.evidence.tailscaleOnline,
                detail: record.evidence.tailscaleLastSeen.map { "last seen \($0.formatted(.relative(presentation: .named)))" })

            if let checked = record.evidence.checkedAt {
                Text("checked \(Fmt.relative(checked))")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
            }
        }
        .elevatedCard()
    }

    // MARK: Capabilities

    private func capabilityCard(_ host: HostCapabilities) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Capabilities")
                    .font(ConsoleFont.cardTitle)
                Spacer()
                if model.hosts.probing {
                    ProgressView().controlSize(.small)
                }
            }

            if host.reachable {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        FactCell(label: "Architecture", value: host.arch ?? "—")
                        FactCell(label: "Cores", value: host.cores.map(String.init) ?? "—")
                        FactCell(label: "Memory", value: host.memoryBytes.map(ConsoleFmt.bytes) ?? "—")
                    }
                    GridRow {
                        FactCell(label: "Disk free", value: host.diskFreeBytes.map(ConsoleFmt.bytes) ?? "—")
                        FactCell(label: "Load", value: host.loadOne.map { String(format: "%.2f", $0) } ?? "—")
                        FactCell(label: "Link", value: host.link.label)
                    }
                }
                .monospacedDigit()

                if !host.tools.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(host.tools.sorted(), id: \.self) { tool in
                            ConsoleBadge(text: tool, tone: .neutral, symbol: "wrench.and.screwdriver")
                        }
                    }
                }
            } else {
                Label(host.error ?? "not reachable over SSH", systemImage: "network.slash")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(StatusTone.bad.ink)
                Text("Probes use BatchMode SSH with your existing ssh_config — no passwords are attempted or stored.")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
            }
        }
        .elevatedCard()
    }

    // MARK: Remote services

    private func servicesCard(_ record: DeviceRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Services on \(record.name)")
                    .font(ConsoleFont.cardTitle)
                Spacer()
                if let checked = record.remoteCheckedAt {
                    Text("read-only · \(Fmt.relative(checked))")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(SurfaceInk.secondary)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(record.remoteServices.enumerated()), id: \.element.id) { index, service in
                    if index > 0 { Hairline().padding(.leading, 52) }
                    HStack(spacing: 10) {
                        EntityIcon(symbol: Iconography.service(service),
                                   tone: service.state.tone, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.friendlyName)
                                .font(ConsoleFont.rowTitle)
                                .lineLimit(1)
                            Text(service.state.label)
                                .font(ConsoleFont.caption)
                                .foregroundStyle(service.state.tone.ink)
                        }
                        Spacer()
                        Text(ConsoleFmt.ports(service.effectivePorts))
                            .font(ConsoleFont.mono(.caption))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: ConsoleMetrics.rowCorner, style: .continuous)
                    .strokeBorder(ConsoleColor.hairline, lineWidth: 1)
            )
        }
        .elevatedCard()
    }

    private func errorCard(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(ConsoleFont.caption)
            .foregroundStyle(StatusTone.warn.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
    }
}

// MARK: - Bits

/// One evidence fact: name, state, and the measurement behind the state.
private struct EvidenceLine: View {
    let label: String
    let state: Bool?
    var detail: String?

    var body: some View {
        HStack(spacing: 8) {
            StatusPip(tone: state == nil ? .unknown : (state! ? .good : .bad), size: 7)
            Text(label)
                .font(ConsoleFont.subtitle)
                .foregroundStyle(.secondary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(ConsoleFont.mono(.caption))
                    .monospacedDigit()
                    .foregroundStyle(SurfaceInk.secondary)
            }
            Text(state == nil ? "not measured" : (state! ? "ok" : "failed"))
                .font(ConsoleFont.caption)
                .foregroundStyle(state == nil ? ConsoleColor.dim
                                : (state! ? StatusTone.good.ink : StatusTone.bad.ink))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FactCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(ConsoleFont.badge.weight(.semibold))
                .foregroundStyle(SurfaceInk.secondary)
                .kerning(0.5)
            Text(value)
                .font(ConsoleFont.mono(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(value)
        }
    }
}
