import SwiftUI
import FleetCore

// Column three: the inspector. A view *of* the current selection — never a
// selection of its own (see `InspectorTarget`). The empty state names what it
// is waiting for, per module, instead of showing a grey void.

struct InspectorPanel: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel

    var body: some View {
        VStack(spacing: 0) {
            inspectorBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        // Bounded like the sidebar is — under ~280pt every value truncates, and
        // past ~420pt the column stops being a margin note and starts competing
        // with the module it is annotating. The bounds themselves are applied by
        // `ConsoleRootView`.
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

    /// Composed from the app's own primitive rather than `ContentUnavailableView`.
    ///
    /// The system view was corrupting this text. At the inspector's old 320pt it
    /// read correctly; the moment the two side columns were mirrored onto the
    /// same 283pt it rendered as "P c:i a qr e s s in the n a to inspect it." —
    /// glyphs drawn on advances measured for a different layout pass. Removing
    /// the caption-font override on the description did not fix it, which is the
    /// part worth recording: the corruption is in how that container measures a
    /// wrapping description at a width it did not expect, not in the font.
    ///
    /// `EmptyPanelView` is the app's own empty state — the one the chrome panels
    /// have always used, and the one place `ConsoleFont.emptyGlyph` was written
    /// for. It carries `fixedSize(horizontal: false, vertical: true)`, which is
    /// the incantation that makes a centred, wrapping caption measure its own
    /// height honestly, and it renders correctly at every column width. It was
    /// called `ToolUnavailableView` until this used it; the name was about where
    /// it happened to be first, not what it is.
    private var emptyState: some View {
        EmptyPanelView(symbol: "sidebar.right", title: "Inspector", detail: emptyHint)
    }

    private var emptyHint: String { console.inspectorHint }
}

// MARK: - Device inspector

/// Column three for a remote node: how you reach it, at what quality, and what
/// it is carrying. Read-only, like everything else across the mesh.
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
