import SwiftUI
import FleetCore

struct InspectorPanel: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel

    var body: some View {
        VStack(spacing: 0) {
            inspectorBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var inspectorBody: some View {
        Group {
            switch console.inspectorTarget() {
            case .process(let pid):
                ProcessInspector(model: model, pid: pid)
            case .volume(let id):
                VolumeInspector(model: model, volumeID: id)
            case .service(let id):
                ServiceInspectorView(model: model, serviceID: id)
            case .unmanaged(let id):
                UnmanagedInspectorView(model: model, unmanagedID: id)
            case .device(let id):
                DeviceInspectorView(model: model, deviceID: id)
            case .none:
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        EmptyPanelView(symbol: "sidebar.right", title: "Inspector", detail: emptyHint)
    }

    private var emptyHint: String { console.inspectorHint }
}

struct DeviceInspectorView: View {
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
                VStack(alignment: .leading, spacing: 14) {
                    InspectorHeader(symbol: "desktopcomputer", tone: record.health.tone,
                                    title: record.name,
                                    subtitle: record.health.label,
                                    subtitleKind: .status)

                    InspectorCard(title: "Addressing") {
                        if let ip = record.tailscaleIP {
                            InspectorLine(key: "Tailnet IP", value: ip, mono: true)
                        }
                        if let host = record.tailscaleHost {
                            InspectorLine(key: "Tailnet name", value: host, mono: true)
                        }
                        if let ip = record.localIP {
                            InspectorLine(key: "LAN IP", value: ip, mono: true)
                        }
                        if let host = record.localHost {
                            InspectorLine(key: "LAN name", value: host, mono: true)
                        }
                        if let port = record.probePort {
                            InspectorLine(key: "Probe", value: "tcp :\(port)", mono: true)
                        }
                    }

                    if let link = capabilities?.link, link.direct != nil {
                        InspectorCard(title: "Link Quality") {
                            InspectorLine(key: "Path", value: link.direct == true ? "direct"
                                          : "relayed via \(link.via ?? "DERP")", mono: true)
                            InspectorLine(key: "Latency", value: ConsoleFmt.latency(link.rttMs),
                                          mono: true)
                            InspectorLine(key: "Interactive", value: link.suitsInteractive
                                          ? "suited — low and stable" : "not suited for interactive work")
                            Text("Worst sample of three, not the mean: a path that is sometimes "
                                 + "8 ms and sometimes 125 ms is a 125 ms path for anything interactive.")
                                .font(ConsoleFont.caption)
                                .foregroundStyle(SurfaceInk.secondary)
                        }
                    }

                    if record.metrics.hasAny {
                        InspectorCard(title: "Last Reported Load") {
                            Text(record.metrics.line)
                                .font(ConsoleFont.mono(.caption))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            if let at = record.metrics.collectedAt {
                                InspectorLine(key: "Collected", value: Fmt.relative(at))
                            }
                        }
                    }

                    if let reachable = record.lastReachableAt {
                        InspectorCard(title: "History") {
                            InspectorLine(key: "Last reachable", value: Fmt.relative(reachable))
                        }
                    }
                }
                .padding(14)
            } else {
                ContentUnavailableView("Device not found", systemImage: "desktopcomputer")
            }
        }
        .scrollContentBackground(.hidden)
    }
}
