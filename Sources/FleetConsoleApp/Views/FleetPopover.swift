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
            // Equal-width anchors keep the tab group on the pane's centerline,
            // including while refresh is in flight or a section is disabled.
            HStack(spacing: 6) {
                IconButton(symbol: "gearshape", help: "Edit FleetConsole configuration") {
                    model.openConfigFile()
                }
                Picker("Section", selection: $tab) {
                    ForEach(enabledTabs) { Text($0.menuTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.regular)
                .accessibilityLabel("Popover section")
                .frame(maxWidth: .infinity)
                refreshButton
            }
            .padding(.horizontal, FleetMetrics.gutter)
            .padding(.vertical, 8)
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
            .frame(height: FleetMetrics.popoverBodyHeight)
            .clipped()
            PopoverFooter(model: model, openDashboard: openDashboard)
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
