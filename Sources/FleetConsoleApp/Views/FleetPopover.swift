import SwiftUI
import FleetCore

/// Legacy section routes retained for menu commands; details now open in the dashboard.
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
    @State private var showingAccount = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                OurosIdentityRow(title: "FleetConsole", detail: model.fleetStatusLine,
                                 tone: model.fleetTint) { FleetBadgeMark(size: $0) }
                Spacer(minLength: 8)
                IconButton(symbol: "square.grid.2x2", help: "Open dashboard and services (⌘0)", action: openDashboard)
                Menu {
                    Button("Refresh") { model.reEvidence() }
                    Button("Edit Configuration…") { model.openConfigFile() }
                    Button("Ouros Account…") { showingAccount = true }
                    Button("Source & Support") { model.openURL("https://github.com/janestreetshiller/fleet-console") }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Configuration and links")
            }
            .padding(.horizontal, FleetMetrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 4)
            QuickView(model: model)
        }
        // The meters determine the dropdown height; never offer a tall body frame.
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: FleetMetrics.popoverWidth)
        .sketchSubstrate(seed: 0.37, grainSeed: 23, ground: false)
        .actionErrorAlert(model: model)
        .sheet(isPresented: $showingAccount) { DeviceManagementView(model: model) }
        .onAppear { consumeRequestedSection() }
        .onChange(of: model.requestedSection) { _, _ in consumeRequestedSection() }
    }

    private func consumeRequestedSection() {
        guard let requested = model.requestedSection else { return }
        model.requestedSection = nil
        guard requested != .quickView else { return }
        openDashboard()
        NotificationCenter.default.post(name: ConsoleCommand.selectModule, object: nil,
            userInfo: [ConsoleCommand.userInfoModule: requested == .processes
                ? ConsoleModule.processes.rawValue : ConsoleModule.services.rawValue])
    }
}
