import SwiftUI
import FleetCore

/// Fixed ownership lanes. Nothing moves unless the controller supplies new data;
/// session detection stays separate from registered ownership.
struct AgentTopologyWorkspace: View {
    let model: AppModel
    let console: ConsoleModel
    @State private var presentation = "Map"
    @State private var account = false
    @State private var review = false
    @State private var selectedOwner = ""
    @State private var limit = 40

    private var graph: FleetTopology? { model.topology }
    private var owners: [FleetTopology.Node] { graph?.nodes.filter { $0.kind == .owner } ?? [] }
    private var services: [FleetTopology.Node] {
        let query = console.search.trimmingCharacters(in: .whitespacesAndNewlines)
        return graph?.nodes.filter {
            $0.kind == .service && (selectedOwner.isEmpty || $0.owner == selectedOwner)
                && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                    || ($0.owner ?? "").localizedCaseInsensitiveContains(query)
                    || ($0.serviceID ?? "").localizedCaseInsensitiveContains(query))
        } ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                HStack {
                    Picker("Presentation", selection: $presentation) {
                        Text("Relations map").tag("Map")
                        Text("Agent roster & inbox").tag("Roster")
                    }.pickerStyle(.segmented).frame(maxWidth: 370)
                    Spacer(minLength: 0)
                }
                if presentation == "Roster" {
                    AgentsContent(model: model, openDashboard: {})
                } else {
                    map
                }
            }.padding(ConsoleMetrics.gutter)
        }
        .sheet(isPresented: $account) { DeviceManagementView(model: model) }
        .sheet(isPresented: $review) { OurosAgentSheet(model: model) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agents & Relations").font(.system(.title2, design: .serif, weight: .semibold))
            Text("FleetConsole / Ouros").font(ConsoleFont.caption).foregroundStyle(SketchInk.accentWarm)
            Text("Trace recorded ownership to services, verified leaders and observed listeners. Detected sessions have their own lane.")
                .font(ConsoleFont.body).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack { accountActions }
                VStack(alignment: .leading, spacing: 8) { accountActions }
            }
            Text("Local monitoring is free. Linked devices use the FleetConsole subscription; Ouros reviews use separate AI credits.")
                .font(ConsoleFont.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var accountActions: some View {
        Button(model.ourosBilling.signedIn ? "Ouros Account & Devices…" : "Connect Ouros…") { account = true }
        Button("Review Problems with Ouros…") { review = true }
            .disabled(!model.connected || !model.ourosBilling.signedIn || model.attention.isEmpty)
            .help("Opens a credit-funded review for your explicit request. Restart proposals require separate approval.")
        Button("Usage & Credits") { model.openURL("https://ouros.md/dashboard#/billing") }
    }

    private var map: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let graph {
                Label(model.connected ? (graph.isStale ? "Stale controller snapshot" : "Controller observations") : "Controller offline · retained observations",
                      systemImage: model.connected && !graph.isStale ? "clock" : "exclamationmark.triangle")
                    .font(ConsoleFont.cardTitle)
                Text("Snapshot \(graph.generatedAt.formatted(date: .abbreviated, time: .standard)) · \(services.count) matching services · values reflect observation time")
                    .font(ConsoleFont.caption).foregroundStyle(.secondary)
                Text("\(owners.count) recorded owners · \(graph.nodes.filter { $0.kind == .session }.count) detected sessions · \(model.awaitingReplyCount) awaiting replies")
                    .font(ConsoleFont.caption).foregroundStyle(.secondary)
                Picker("Recorded owner", selection: $selectedOwner) {
                    Text("All recorded owners").tag("")
                    ForEach(owners) { Text($0.title).tag($0.title) }
                }.frame(maxWidth: 340)
                if services.isEmpty {
                    ContentUnavailableView("No matching service records", systemImage: "point.3.connected.trianglepath.dotted",
                                           description: Text("Launch work through fleetctl to record an owner and purpose. Detected sessions appear below without inferred ownership."))
                    if !console.search.isEmpty { Button("Clear Search") { console.search = "" } }
                } else {
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 32) {
                                Text("RECORDED OWNER").frame(width: 150, alignment: .leading)
                                Text("SERVICE / GROUP RESOURCES").frame(width: 290, alignment: .leading)
                                Text("OBSERVED EVIDENCE").frame(width: 260, alignment: .leading)
                            }.font(ConsoleFont.micro).foregroundStyle(.secondary).padding(.bottom, 12)
                            ForEach(Array(services.prefix(limit))) { service in
                                relationshipRow(service, graph: graph)
                                Divider().padding(.vertical, 10)
                            }
                        }
                    }
                    if services.count > limit {
                        Button("Show next 40 services (\(services.count - limit) remaining)") { limit += 40 }
                    }
                }
                sessions(graph)
                DisclosureGroup("Evidence & coverage") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(graph.limitations, id: \.self) { Text($0) }
                        Text("Edges reflect timestamped controller evidence. Declared ports do not create listener edges. Missing or stale samples are unavailable.")
                    }.font(ConsoleFont.caption).foregroundStyle(.secondary)
                }
                Text("CLI: fleetctl topology --json").font(ConsoleFont.mono()).textSelection(.enabled)
            } else {
                ContentUnavailableView("Waiting for the controller", systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text("No snapshot has arrived. Run fleetctl doctor to check the local controller."))
            }
        }
        .onChange(of: selectedOwner) { _, _ in limit = 40 }
        .onChange(of: console.search) { _, _ in limit = 40 }
    }

    private func relationshipRow(_ service: FleetTopology.Node, graph: FleetTopology) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(service.owner ?? "Unavailable", systemImage: "person.crop.square")
                    .font(ConsoleFont.rowTitle)
                if let owner = owners.first(where: { $0.title == service.owner }) {
                    Text(owner.detail).font(ConsoleFont.micro).foregroundStyle(.secondary)
                }
            }.frame(width: 150, alignment: .leading)
            Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityLabel("Recorded ownership")
            Button {
                console.selectedServiceID = service.serviceID
                console.selectedUnmanagedID = nil
                console.inspectorRevealed = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(service.title).font(ConsoleFont.cardTitle)
                    Text(service.detail).font(ConsoleFont.micro).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("CPU \(service.cpuPct.map(Fmt.cpu) ?? "unavailable") · RAM \(service.memMB.map(Fmt.mem) ?? "unavailable")")
                        .font(ConsoleFont.caption).monospacedDigit()
                    if let record = service.serviceID.flatMap({ model.service(id: $0) }) {
                        Text(record.purpose).font(ConsoleFont.caption).lineLimit(2)
                        Text("Lease \(record.leaseExpiresAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(ConsoleFont.micro).foregroundStyle(.secondary)
                    }
                    Text("Inspect service →").font(ConsoleFont.caption).foregroundStyle(Color.accentColor)
                }.padding(10).frame(width: 290, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(console.selectedServiceID == service.serviceID ? SketchInk.accentWarm : .clear, lineWidth: 2) }
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("topology.service.\(service.serviceID ?? "")")
            let evidence = graph.nodes.filter { $0.serviceID == service.serviceID && $0.kind != .service }
            Image(systemName: evidence.isEmpty ? "minus" : "arrow.right").foregroundStyle(.secondary)
                .accessibilityLabel(evidence.isEmpty ? "No verified relation" : "Observed evidence")
            VStack(alignment: .leading, spacing: 8) {
                if evidence.isEmpty { Text("No fresh verified leader or listener observations").foregroundStyle(.secondary) }
                ForEach(evidence) { node in
                    Label(node.title, systemImage: node.kind == .listener ? "network" : "gearshape")
                    Text(node.detail).font(ConsoleFont.micro).foregroundStyle(.secondary)
                }
                if let date = service.observedAt {
                    Text("Checked \(date.formatted(date: .omitted, time: .standard))")
                        .font(ConsoleFont.micro).foregroundStyle(.secondary)
                }
            }.font(ConsoleFont.caption).frame(width: 260, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private func sessions(_ graph: FleetTopology) -> some View {
        let query = console.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let detected = graph.nodes.filter { $0.kind == .session && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query)) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Detected sessions · ownership unlinked").font(ConsoleFont.cardTitle)
            if detected.isEmpty { Text("No matching detected sessions in this snapshot.").foregroundStyle(.secondary) }
            ForEach(Array(detected.prefix(40))) { session in
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).font(ConsoleFont.rowTitle)
                    Text(session.detail).font(ConsoleFont.caption).foregroundStyle(.secondary)
                    Text("CPU \(session.cpuPct.map(Fmt.cpu) ?? "unavailable") · RAM \(session.memMB.map(Fmt.mem) ?? "unavailable")")
                        .font(ConsoleFont.caption).monospacedDigit()
                }.accessibilityElement(children: .combine)
            }
            if detected.count > 40 { Text("Showing 40 of \(detected.count) sessions. Use search or fleetctl topology for the complete snapshot.").font(ConsoleFont.caption) }
        }
    }
}
