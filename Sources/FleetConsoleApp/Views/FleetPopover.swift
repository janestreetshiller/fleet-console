import SwiftUI
import FleetCore

/// Shared by menu commands and the five-tab popover.
enum FleetSection: String, CaseIterable, Identifiable {
    case quickView = "Quick View"
    case services = "Services"
    case agents = "Agents"
    case processes = "Processes"
    case connections = "Connections"

    var id: String { rawValue }
    var menuTitle: String { self == .connections ? "Network" : rawValue }

    @MainActor
    func isEnabled(_ settings: Settings) -> Bool {
        switch self {
        case .quickView: return true
        case .services: return settings.sections.services
        case .agents: return settings.sections.agents
        case .processes: return settings.sections.processes
        case .connections: return settings.sections.network
        }
    }
}

struct FleetPopover: View {
    @Bindable var model: AppModel
    var openDashboard: () -> Void
    var registration: AgentRegistrationModel = .shared
    @State private var tab: FleetSection = .quickView

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                switch tab {
                case .quickView: QuickView(model: model)
                case .services: ServicesContent(model: model, openDashboard: openDashboard)
                case .agents: AgentsContent(model: model, openDashboard: openDashboard, registration: registration)
                case .processes: ProcessesContent(model: model, openDashboard: openDashboard)
                case .connections:
                    VStack(spacing: 0) {
                        ConnectionsPopover(model: model, openDashboard: openDashboard, embedded: true)
                        Divider()
                        NetworkAdminFooter(model: model)
                    }
                }
            }
            .frame(maxHeight: FleetMetrics.popoverBodyHeight)
        }
        .frame(width: FleetMetrics.popoverWidth)
        .sketchSubstrate(seed: 0.37, grainSeed: 23, ground: false)
        .onAppear { consumeRequestedSection() }
        .onChange(of: model.requestedSection) { _, _ in consumeRequestedSection() }
        .onChange(of: enabledTabs) { _, tabs in
            if !tabs.contains(tab) { tab = .quickView }
        }
    }

    private var enabledTabs: [FleetSection] {
        FleetSection.allCases.filter { $0.isEnabled(model.settings) }
    }

    private func consumeRequestedSection() {
        guard let requested = model.requestedSection else { return }
        tab = enabledTabs.contains(requested) ? requested : .quickView
        model.requestedSection = nil
    }

    /// Everything the popover used to split between a top bar and a bottom
    /// ribbon, in one header: who and how the fleet is, the way out to the
    /// dashboard, and the section tabs. Nothing is pinned under the content, so
    /// the content ends where it ends.
    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                OurosIdentityRow(title: "FleetConsole", detail: model.fleetStatusLine,
                                 tone: model.fleetTint) { FleetBadgeMark(size: $0) }
                Spacer(minLength: 8)
                Button(action: openDashboard) {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.trailing, 4)
                .help("Open Dashboard (⌘0)")
                refreshButton
                linksMenu
            }
            // Equal-width segments on the pane's centerline, the full width of
            // the header, so the tabs line up with the content under them.
            Picker("Section", selection: $tab) {
                ForEach(enabledTabs) { Text($0.menuTitle).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Popover section")
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, FleetMetrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var linksMenu: some View {
        Menu {
            Button("Edit Configuration…") { model.openConfigFile() }
            Divider()
            Button("Ouros Website") { model.openURL("https://ouros.md") }
            Button("Source & Support") { model.openURL("https://github.com/janestreetshiller/fleet-console") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(FleetFont.body.weight(.medium))
                .foregroundStyle(SurfaceInk.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: FleetMetrics.iconButtonSize, height: FleetMetrics.iconButtonSize)
        .help("Configuration and links")
        .accessibilityLabel("Configuration and links")
    }

    @ViewBuilder private var refreshButton: some View {
        if model.isReconciling {
            ProgressView().controlSize(.small).scaleEffect(0.6)
                .frame(width: FleetMetrics.iconButtonSize, height: FleetMetrics.iconButtonSize)
                .accessibilityLabel("Refreshing FleetConsole")
        } else {
            IconButton(symbol: "arrow.clockwise", help: "Refresh FleetConsole") { model.reEvidence() }
        }
    }
}
