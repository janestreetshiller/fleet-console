import AppKit
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
                AgentMenuButton { metric in
                    model.investigate(.metric(metric, model: model))
                }
                .frame(height: FleetMetrics.iconButtonSize)
                .fixedSize(horizontal: true, vertical: false)
                ConfigurationMenuButton(
                    refresh: { model.reEvidence() },
                    editConfiguration: { model.openConfigFile() },
                    showAccount: { showingAccount = true },
                    openSource: { model.openURL("https://github.com/janestreetshiller/fleet-console") }
                )
                .frame(width: FleetMetrics.iconButtonSize, height: FleetMetrics.iconButtonSize)
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
                ? ConsoleModule.processes.rawValue : ConsoleModule.services.rawValue,
                       "operationsSection": requested == .connections ? "Network" : requested == .agents ? "Agents" : "Services"])
    }
}

/// One Agent menu for the four meters. A label on every instrument repeated
/// the same word across the dropdown.
private struct AgentMenuButton: NSViewRepresentable {
    var investigate: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> HoverButton {
        let button = HoverButton()
        button.title = "Agent"
        button.imagePosition = .noImage
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.isBordered = false
        button.showsBorderOnlyWhileMouseInside = false
        button.bezelStyle = .shadowlessSquare
        button.setButtonType(.momentaryChange)
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel("Agent")
        button.toolTip = "Investigate a meter"
        button.target = context.coordinator
        button.action = #selector(Coordinator.pop(_:))
        return button
    }

    func updateNSView(_ button: HoverButton, context: Context) {
        context.coordinator.investigate = investigate
        button.isBordered = false
        button.showsBorderOnlyWhileMouseInside = false
    }

    final class Coordinator: NSObject {
        var investigate: (String) -> Void = { _ in }
        private let meters = [("CPU", "cpu"), ("Memory", "memory"), ("Disk", "disk"), ("Network", "network")]

        @objc func pop(_ sender: NSButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for (title, metric) in meters {
                let item = NSMenuItem(title: title, action: #selector(didPick(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = metric
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
        }

        @objc func didPick(_ sender: NSMenuItem) {
            guard let metric = sender.representedObject as? String else { return }
            investigate(metric)
        }
    }
}

/// Pull-down with the bezel and the hover plate turned off. SwiftUI's
/// borderless menu button still draws a hit-box border while the pointer is
/// over it, and that border stays up in the menu-bar dropdown.
private struct ConfigurationMenuButton: NSViewRepresentable {
    var refresh: () -> Void
    var editConfiguration: () -> Void
    var showAccount: () -> Void
    var openSource: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> HoverButton {
        let button = HoverButton()
        let symbol = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        symbol?.isTemplate = true
        button.image = symbol
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.showsBorderOnlyWhileMouseInside = false
        button.bezelStyle = .shadowlessSquare
        button.setButtonType(.momentaryChange)
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel("Configuration and links")
        button.toolTip = "Configuration and links"
        button.target = context.coordinator
        button.action = #selector(Coordinator.pop(_:))
        return button
    }

    func updateNSView(_ button: HoverButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.refresh = refresh
        coordinator.editConfiguration = editConfiguration
        coordinator.showAccount = showAccount
        coordinator.openSource = openSource
        button.isBordered = false
        button.showsBorderOnlyWhileMouseInside = false
    }

    final class Coordinator: NSObject {
        var refresh: () -> Void = {}
        var editConfiguration: () -> Void = {}
        var showAccount: () -> Void = {}
        var openSource: () -> Void = {}

        @objc func pop(_ sender: NSButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            let entries: [(String, Selector)] = [
                ("Refresh", #selector(didRefresh)),
                ("Edit Configuration…", #selector(didEdit)),
                ("Ouros Account…", #selector(didAccount)),
                ("Source & Support", #selector(didSource)),
            ]
            for (title, action) in entries {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
            // Non-flipped view: y = 0 is the button's bottom edge, so the menu opens downward.
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
        }

        @objc func didRefresh() { refresh() }
        @objc func didEdit() { editConfiguration() }
        @objc func didAccount() { showAccount() }
        @objc func didSource() { openSource() }
    }
}

/// Template image, tint on hover, no bezel. `showsBorderOnlyWhileMouseInside`
/// is the plate the dropdown was keeping around this control.
private final class HoverButton: NSButton {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        contentTintColor = .labelColor
    }

    override func mouseExited(with event: NSEvent) {
        contentTintColor = .secondaryLabelColor
    }
}
