import SwiftUI
import AppKit
import FleetCore

/// Agent-first spatial awareness. The projection is bounded and refreshed by
/// existing observations; there is no physics loop, extra poller or paid request.
struct AgentAwarenessWorkspace: View {
    let model: AppModel
    @Bindable var console: ConsoleModel
    @State private var graph: AwarenessGraph?
    @State private var selectedID: String?
    @State private var zoom: CGFloat = 1
    // Observation bounds can change without moving any existing world node.
    // Only fitting or focusing changes this camera anchor, never refresh().
    @State private var worldCenter: CGPoint = .zero
    @State private var pan: CGSize = .zero
    @State private var dragOrigin: CGSize?
    @State private var magnificationOrigin: CGFloat?
    @State private var viewport: CGSize = .zero
    @State private var didFit = false
    @State private var didFitActivity = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selected: AwarenessGraph.Node? { graph?.nodes.first { $0.id == selectedID } }
    private var query: String { console.search.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        GeometryReader { geometry in
            let nodes = visibleNodes
            let ids = Set(nodes.map(\.id))
            let edges = (graph?.edges ?? []).filter { ids.contains($0.source) && ids.contains($0.target) }
            let related = relatedIDs(edges: edges)
            ZStack(alignment: .topLeading) {
                AwarenessInk.ground.ignoresSafeArea()
                canvas(nodes: nodes, edges: edges, related: related, size: geometry.size)
                    .accessibilityIdentifier("awareness.canvas")
                if nodes.isEmpty {
                    ContentUnavailableView {
                        Label(query.isEmpty ? "Waiting for activity observations" : "No matching activity", systemImage: "point.3.connected.trianglepath.dotted")
                    } description: {
                        Text(query.isEmpty ? "Detected agent sessions and managed work appear here as they are observed." : "Search agents, projects, services or processes.")
                    } actions: {
                        if !query.isEmpty { Button("Clear Search") { console.search = "" } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                VStack(alignment: .leading, spacing: 8) {
                    header
                    Spacer()
                    HStack(alignment: .bottom) {
                        minimap(size: geometry.size)
                        Spacer()
                        controls
                    }
                }
                .padding(ConsoleMetrics.gutter)
                if let selected {
                    detail(selected)
                        .frame(width: min(320, max(240, geometry.size.width * 0.28)))
                        .padding(ConsoleMetrics.gutter)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .clipped()
            .onAppear { viewport = geometry.size; refresh(); if !didFit { initialFit(size: geometry.size) } }
            .onChange(of: geometry.size) { _, size in
                viewport = size
                if !didFit { initialFit(size: size) }
            }
        }
        .onChange(of: model.lastSnapshotAt) { _, _ in refresh() }
        .onChange(of: model.processes.capturedAt) { _, _ in refresh() }
        .onChange(of: model.topology) { _, _ in refresh() }
        .onChange(of: console.search) { _, _ in fit(size: viewport, nodes: visibleNodes) }
        .onExitCommand { selectedID = nil }
    }

    private var visibleNodes: [AwarenessGraph.Node] {
        guard let graph else { return [] }
        guard !query.isEmpty else { return graph.nodes }
        let matched = Set(graph.nodes.filter {
            [$0.title, $0.subtitle, $0.activity ?? "", $0.projectPath ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
        }.map(\.id))
        var included = matched
        for edge in graph.edges where matched.contains(edge.source) || matched.contains(edge.target) {
            included.insert(edge.source); included.insert(edge.target)
        }
        return graph.nodes.filter { included.contains($0.id) }
    }

    private func relatedIDs(edges: [AwarenessGraph.Edge]) -> Set<String> {
        guard let selectedID else { return [] }
        var ids: Set<String> = [selectedID]
        for edge in edges where edge.source == selectedID || edge.target == selectedID {
            ids.insert(edge.source); ids.insert(edge.target)
        }
        return ids
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agent awareness").font(ConsoleFont.moduleTitle)
                .accessibilityAddTraits(.isHeader)
            let nodes = graph?.nodes ?? []
            Text("\(nodes.filter { $0.kind == .session }.count) detected sessions · \(nodes.filter { $0.kind == .project }.count) projects · \(nodes.filter { $0.kind == .service }.count) managed services")
                .font(ConsoleFont.caption).foregroundStyle(SurfaceInk.secondary)
            AwarenessObservationStatus(model: model)
            if !model.attention.isEmpty {
                Button("Review findings (\(model.attention.count))") { console.goHome() }
                    .font(ConsoleFont.caption)
            }
        }
        .padding(ConsoleMetrics.cardPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ConsoleMetrics.cardCorner))
        .accessibilityIdentifier("awareness.summary")
    }

    private func canvas(nodes: [AwarenessGraph.Node], edges: [AwarenessGraph.Edge], related: Set<String>, size: CGSize) -> some View {
        let index = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        return ZStack {
            Canvas { context, canvas in
                // A spatial reference grid moves with the camera, not a data trace.
                let step: CGFloat = max(18, 40 * zoom)
                let ox = (canvas.width / 2 + pan.width).truncatingRemainder(dividingBy: step)
                let oy = (canvas.height / 2 + pan.height).truncatingRemainder(dividingBy: step)
                for x in stride(from: ox, through: canvas.width, by: step) {
                    for y in stride(from: oy, through: canvas.height, by: step) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(AwarenessInk.grid))
                    }
                }
                for node in nodes where node.kind == .project {
                    let center = point(node.position, size: size)
                    let diameter = 560 * zoom
                    let circle = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
                    context.fill(Path(ellipseIn: circle), with: .color(related.contains(node.id) ? AwarenessInk.selectedHalo : AwarenessInk.halo))
                }
                for edge in edges {
                    guard let source = index[edge.source], let target = index[edge.target] else { continue }
                    let a = point(source.position, size: size)
                    let b = point(target.position, size: size)
                    let focused = selectedID == edge.source || selectedID == edge.target
                    var path = Path()
                    path.move(to: a)
                    let bend = (b.x - a.x) * 0.5
                    path.addCurve(to: b, control1: CGPoint(x: a.x + bend, y: a.y), control2: CGPoint(x: b.x - bend, y: b.y))
                    context.stroke(path, with: .color(focused ? .accentColor : AwarenessInk.connection),
                                   style: StrokeStyle(lineWidth: focused ? 2 : 1, lineCap: .round))
                    if focused {
                        let label = Text(edge.label).font(ConsoleFont.micro).foregroundStyle(.secondary)
                        context.draw(label, at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 12))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                let origin = dragOrigin ?? pan
                if dragOrigin == nil { dragOrigin = pan }
                pan = CGSize(width: origin.width + value.translation.width, height: origin.height + value.translation.height)
            }.onEnded { _ in dragOrigin = nil })
            .onTapGesture { selectedID = nil }
            ForEach(nodes) { node in
                Button { selectedID = node.id } label: {
                    AwarenessNodeView(node: node, selected: node.id == selectedID,
                                      related: selectedID == nil || related.contains(node.id))
                        .equatable()
                }
                .buttonStyle(.plain)
                .frame(width: node.size.width, height: node.size.height)
                .scaleEffect(zoom)
                .position(point(node.position, size: size))
                .accessibilityIdentifier("awareness.node.\(node.id)")
                .contextMenu {
                    Button("Focus relationships") { selectedID = node.id; focus(node, size: size) }
                    if let pid = node.pid { Button("Inspect current process") { console.inspectConsoleProcess(pid) } }
                    if let id = node.serviceID { Button("Inspect service") { console.inspectConsoleService(id) } }
                }
            }
        }
        .simultaneousGesture(MagnificationGesture().onChanged { value in
            if magnificationOrigin == nil { magnificationOrigin = zoom }
            zoom = min(2.5, max(0.2, (magnificationOrigin ?? 1) * value))
        }.onEnded { _ in magnificationOrigin = nil })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity relationship map. Drag to pan; use zoom controls or pinch to explore.")
    }

    private func detail(_ node: AwarenessGraph.Node) -> some View {
        VStack(alignment: .leading, spacing: ConsoleMetrics.cardGap) {
            HStack {
                Label(node.title, systemImage: node.symbol).font(ConsoleFont.cardTitle)
                Spacer(minLength: 8)
                Button { selectedID = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Close activity detail")
                    .accessibilityIdentifier("awareness.close")
            }
            Text(node.subtitle).font(ConsoleFont.caption).foregroundStyle(SurfaceInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let activity = node.activity, !activity.isEmpty {
                Text("Latest published activity").font(ConsoleFont.caption.weight(.medium))
                Text(activity).font(ConsoleFont.body).lineLimit(8).textSelection(.enabled)
            }
            let connections = graph?.edges.filter { $0.source == node.id || $0.target == node.id } ?? []
            if !connections.isEmpty {
                Divider()
                Text("Observed relationships").font(ConsoleFont.cardTitle)
                ForEach(connections.prefix(8)) { edge in
                    let otherID = edge.source == node.id ? edge.target : edge.source
                    if let other = graph?.nodes.first(where: { $0.id == otherID }) {
                        Button { selectedID = other.id; focus(other, size: viewport) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(other.title).font(ConsoleFont.rowTitle)
                                Text(edge.label).font(ConsoleFont.micro).foregroundStyle(SurfaceInk.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help(edge.evidence)
                    }
                }
            }
            HStack {
                Button("Focus") { focus(node, size: viewport) }
                    .accessibilityIdentifier("awareness.focus")
                if let id = node.serviceID {
                    Button("Inspect service") { console.inspectConsoleService(id) }
                } else if let pid = node.pid {
                    Button("Inspect current PID") { console.inspectConsoleProcess(pid) }
                } else if let path = node.projectPath {
                    Button("Open project") { model.revealInFinder(path) }
                }
            }
            Text("Connections show observed evidence, not inferred dependencies or agent reasoning.")
                .font(ConsoleFont.micro).foregroundStyle(SurfaceInk.secondary)
        }
        .padding(ConsoleMetrics.cardPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ConsoleMetrics.cardCorner))
        .overlay { RoundedRectangle(cornerRadius: ConsoleMetrics.cardCorner).strokeBorder(AwarenessInk.edge, lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("awareness.detail")
    }

    private var controls: some View {
        HStack(spacing: ConsoleMetrics.panelInset) {
            Button { changeZoom(1 / 1.2) } label: { Image(systemName: "minus.magnifyingglass") }
                .help("Zoom out").accessibilityIdentifier("awareness.zoom.out")
            Text("\(Int(zoom * 100))%").font(ConsoleFont.mono(.caption)).monospacedDigit()
                .accessibilityIdentifier("awareness.zoom.value")
            Button { changeZoom(1.2) } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Zoom in").accessibilityIdentifier("awareness.zoom.in")
            Divider().frame(height: ConsoleMetrics.gutter)
            Button("Fit map") { fit(size: viewport) }.accessibilityIdentifier("awareness.fit")
        }
        .buttonStyle(.borderless)
        .padding(ConsoleMetrics.cardPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ConsoleMetrics.cardCorner))
    }

    private func minimap(size: CGSize) -> some View {
        Button { fit(size: size) } label: {
            Canvas { context, canvas in
                guard let graph, graph.bounds.width > 0, graph.bounds.height > 0 else { return }
                let scale = min(canvas.width / graph.bounds.width, canvas.height / graph.bounds.height)
                for node in graph.nodes {
                    let x = (node.position.x - graph.bounds.minX) * scale
                    let y = (node.position.y - graph.bounds.minY) * scale
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: node.kind == .session ? 5 : 3, height: node.kind == .session ? 5 : 3)),
                                 with: .color(node.id == selectedID ? .accentColor : AwarenessInk.connection))
                }
            }
            .frame(width: AwarenessMetrics.minimapSize.width, height: AwarenessMetrics.minimapSize.height)
            .padding(ConsoleMetrics.panelInset)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ConsoleMetrics.cardCorner))
        }
        .buttonStyle(.plain).help("Activity overview · fit entire map")
        .accessibilityLabel("Activity overview. Fit entire map.")
    }

    private func point(_ position: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: (position.x - worldCenter.x) * zoom + size.width / 2 + pan.width,
                y: (position.y - worldCenter.y) * zoom + size.height / 2 + pan.height)
    }

    private func initialFit(size: CGSize) {
        guard let graph, size.width >= 320, size.height >= 300 else { return }
        if let agent = graph.nodes.first(where: { $0.kind == .session }) {
            let peers = graph.nodes.filter { $0.kind == .session && $0.projectPath == agent.projectPath }.prefix(6)
            let primary = Set(peers.map(\.id))
            var ids = primary
            for edge in graph.edges where primary.contains(edge.source) || primary.contains(edge.target) {
                ids.insert(edge.source); ids.insert(edge.target)
            }
            fit(size: size, nodes: graph.nodes.filter { ids.contains($0.id) }, minimumZoom: 0.72)
            didFitActivity = true
        } else {
            fit(size: size, minimumZoom: 0.65)
        }
    }

    private func fit(size: CGSize, nodes: [AwarenessGraph.Node]? = nil, minimumZoom: CGFloat = 0.2) {
        // NSHostingView measures provisional tiny frames before the shipping
        // window is sized. Never commit those measurements as a fitted camera.
        guard let graph, size.width >= 320, size.height >= 300 else { return }
        let bounds = nodes.map { list in list.reduce(CGRect.null) { $0.union(CGRect(x: $1.position.x - $1.size.width / 2, y: $1.position.y - $1.size.height / 2, width: $1.size.width, height: $1.size.height)) } } ?? graph.bounds
        guard !bounds.isNull else { return }
        zoom = min(1.2, max(minimumZoom, min((size.width - 100) / max(1, bounds.width), (size.height - 220) / max(1, bounds.height))))
        worldCenter = bounds.center
        pan = CGSize(width: 0, height: 35)
        didFit = true
    }

    private func focus(_ node: AwarenessGraph.Node, size: CGSize) {
        let action = {
            zoom = min(1.1, max(zoom, 0.85))
            worldCenter = node.position
            pan = CGSize(width: -min(140, size.width * 0.12), height: 0)
        }
        if reduceMotion { action() } else { withAnimation(.easeOut(duration: 0.25), action) }
    }

    private func changeZoom(_ factor: CGFloat) { zoom = min(2.5, max(0.2, zoom * factor)) }

    private func refresh() {
        let value = AwarenessGraph.build(sessions: model.sessions, processes: model.processes.rows,
                                         processCapturedAt: model.processes.capturedAt, topology: model.topology)
        graph = value
        if let selectedID, !value.nodes.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
        if !didFit || (!didFitActivity && value.nodes.contains(where: { $0.kind == .session })) { initialFit(size: viewport) }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

private struct AwarenessNodeView: View, Equatable {
    let node: AwarenessGraph.Node
    let selected: Bool
    let related: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: node.kind == .session ? 8 : 4) {
            HStack(spacing: 8) {
                Image(systemName: node.symbol).foregroundStyle(Color.accentColor)
                Text(node.title).font(node.kind == .session ? ConsoleFont.cardTitle : ConsoleFont.rowTitle.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if node.kind == .session { Text("Agent").font(ConsoleFont.micro).foregroundStyle(SurfaceInk.secondary) }
            }
            Text(node.subtitle).font(ConsoleFont.micro).foregroundStyle(SurfaceInk.secondary).lineLimit(2)
            if node.kind == .session {
                Text(node.activity?.isEmpty == false ? node.activity! : "No published activity")
                    .font(ConsoleFont.caption).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if node.cpuPercent != nil || node.memoryMB != nil {
                HStack(spacing: 8) {
                    if let cpu = node.cpuPercent { Text(Fmt.cpu(cpu) + " CPU") }
                    if let memory = node.memoryMB { Text(Fmt.mem(memory)) }
                }.font(ConsoleFont.micro).monospacedDigit().foregroundStyle(SurfaceInk.secondary)
            }
        }
        .padding(node.kind == .session ? ConsoleMetrics.cardPadding : ConsoleMetrics.panelInset)
        .frame(width: node.size.width, height: node.size.height, alignment: .topLeading)
        .background(AwarenessInk.node, in: RoundedRectangle(cornerRadius: node.kind == .project ? 21 : 8))
        .overlay {
            RoundedRectangle(cornerRadius: node.kind == .project ? 21 : 8)
                .strokeBorder(selected ? Color.accentColor : AwarenessInk.edge, lineWidth: selected ? 2 : 0.5)
        }
        .shadow(color: AwarenessInk.shadow, radius: node.kind == .session ? 14 : 5, y: 4)
        .opacity(related ? 1 : AwarenessInk.faded)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct AwarenessObservationStatus: View {
    let model: AppModel
    var body: some View {
        let _ = model.clockTick
        HStack(spacing: 8) {
            Label(model.connected ? "Controller connected" : "Controller offline · retained activity",
                  systemImage: model.connected ? "circle.fill" : "exclamationmark.circle")
            if let time = model.processes.capturedAt { Text("Processes \(Fmt.relative(time))") }
        }
        .font(ConsoleFont.micro).foregroundStyle(SurfaceInk.secondary)
    }
}
