import SwiftUI
import FleetCore

/// The three halves of the menu-bar popover.
///
/// Declared outside the view because it is not only the view's state: the
/// status-item dropdown routes to a section by name, so `AppModel` has to be
/// able to name one without importing the popover's internals.
enum FleetSection: String, CaseIterable, Identifiable {
    case services = "Services"
    case agents = "Agents"
    case processes = "Processes"
    case connections = "Connections"

    var id: String { rawValue }

    /// Whether config leaves this section switched on. A section that is off is
    /// absent from the picker entirely rather than present-and-disabled — a
    /// segment you can see and cannot press is the dead chrome rule 10 bans.
    @MainActor
    func isEnabled(_ settings: Settings) -> Bool {
        switch self {
        case .services: return settings.sections.services
        case .agents: return settings.sections.agents
        case .processes: return settings.sections.processes
        case .connections: return settings.sections.network
        }
    }

    /// What the dropdown calls it. "Network" everywhere it is user-facing —
    /// the segmented control has said Network since it was added, and a menu
    /// item labelled Connections opening a tab labelled Network is the same
    /// one-command-three-labels problem as Show Console / Open Dashboard.
    var menuTitle: String {
        self == .connections ? "Network" : rawValue
    }
}

/// The one menu-bar popover — **Fleet**.
///
/// Services and agents were separate menu-bar items for a while, which was one
/// item too many: an agent *owns* services, so the two are the same subject seen
/// from either end. They are now two tabs of one popover — you keep both views,
/// but the menu bar keeps one icon. Connections joined them the same way, which
/// is why the app puts up one status item and not the two this file's comments
/// (and the design system's menu-bar table) went on describing for a while.
struct FleetPopover: View {
    @Bindable var model: AppModel
    var openDashboard: () -> Void

    typealias Tab = FleetSection

    @State private var tab: Tab = .services

    var body: some View {
        VStack(spacing: 0) {
            // The menu-bar icon already identifies Fleet. Repeating the app name
            // here crowds out the actual navigation, so this header is purposefully
            // only the destinations and their contextual actions.
            HStack(spacing: 8) {
                Picker("Section", selection: $tab) {
                    ForEach(enabledTabs) { item in
                        Text(badgeLabel(for: item)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: .infinity)

                // A constant-width slot, always two buttons wide.
                //
                // This is why the picker changed size when you clicked it: the
                // cluster held two buttons on some tabs and one on others, and
                // the picker beside it is `maxWidth: .infinity`, so *selecting a
                // tab* changed how much width was left for the control that
                // selects tabs. Reserving the space makes the segmented control
                // one fixed size for the life of the popover.
                HStack(spacing: 2) {
                    switch tab {
                    case .connections:
                        IconButton(symbol: "gearshape", help: "Open Network settings") {
                            model.network.openSettings(.network)
                        }
                        reEvidenceButton(help: "Re-probe connections, devices and the controller")
                    case .processes:
                        IconButton(symbol: "square.grid.2x2", help: "Open Activity Monitor") {
                            model.openActivityMonitor()
                        }
                        reEvidenceButton(help: "Re-sample the process table and re-run the sweep")
                    case .services:
                        Spacer(minLength: 0)
                        reEvidenceButton(help: "Re-capture the process table, re-run the "
                                         + "reconciliation sweep and re-probe this machine")
                    case .agents:
                        Spacer(minLength: 0)
                        reEvidenceButton(help: "Re-scan for agent sessions and re-run the sweep")
                    }
                }
                .frame(width: FleetMetrics.actionSlot, alignment: .trailing)
            }
            .padding(.horizontal, FleetMetrics.gutter)
            .padding(.vertical, 8)
            Divider()

            HStack(spacing: 13) {
                Text("CPU \(model.system.cpu.sampled ? ConsoleFmt.utilPercent(model.system.cpu.usage) : "—")")
                Spacer(minLength: 0)
                Text("RAM \(ConsoleFmt.utilPercent(model.system.memory.usedShare))")
                Spacer(minLength: 0)
                Text("↓ \(ConsoleFmt.byteRate(model.system.network.downloadBytesPerSec))")
            }
            .font(FleetFont.caption)
            .monospacedDigit()
            .padding(.horizontal, FleetMetrics.gutter)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            Divider()

            switch tab {
            case .services:
                ServicesContent(model: model, openDashboard: openDashboard)
            case .agents:
                AgentsContent(model: model, openDashboard: openDashboard)
            case .processes:
                ProcessesContent(model: model, openDashboard: openDashboard)
            case .connections:
                ConnectionsPopover(model: model, openDashboard: openDashboard, embedded: true)
            }

            Divider()
            if tab == .connections {
                NetworkAdminFooter(model: model)
                Divider()
            }
            PopoverFooter(model: model, openDashboard: openDashboard)
        }
        .frame(width: FleetMetrics.popoverWidth)
        // One substrate for the popover, not one per section. The two sections
        // that carried their own texture were the two that happened to be
        // written last, and a page whose grain restarts when you switch tabs is
        // not a page.
        .sketchSubstrate(seed: 0.37, grainSeed: 23, ground: false)
        .onAppear {
            // An explicit request from the dropdown wins; it is the one case
            // where the user named the destination. Otherwise open on whichever
            // half actually needs you.
            if !consumeRequestedSection(), model.awaitingReplyCount > 0 {
                tab = .agents
            }
        }
        // ...and again on the property itself, because an NSPopover's hosting
        // controller is built once and reused. Whether `onAppear` runs a second
        // time is a detail of when AppKit detaches that view from the window,
        // which is not a thing a navigation intent should depend on.
        .onChange(of: model.requestedSection) { _, _ in
            _ = consumeRequestedSection()
        }
    }

    /// The sections config leaves switched on, in declaration order.
    ///
    /// Never empty: switching every section off would leave a picker with no
    /// segments and a popover with nothing under it, so Services survives as the
    /// floor. A configuration that turns the whole app off is a configuration
    /// error, and the honest response is to keep one surface rather than to
    /// render a void.
    private var enabledTabs: [Tab] {
        let enabled = Tab.allCases.filter { $0.isEnabled(model.settings) }
        return enabled.isEmpty ? [.services] : enabled
    }

    /// Moves to a section the dropdown asked for and clears the request, so a
    /// second opening does not re-run a stale intent. Returns whether it acted.
    @discardableResult
    private func consumeRequestedSection() -> Bool {
        guard let requested = model.requestedSection else { return false }
        tab = requested
        model.requestedSection = nil
        return true
    }

    /// The segment title, and nothing else.
    ///
    /// These used to carry live counts — "Services 1", "Agents 3!" — and a
    /// segmented control sizes its segments to their content, so every count
    /// that ticked over resized the control and shuffled the segments under the
    /// pointer. A number that moves does not belong in the thing you aim at.
    ///
    /// Nothing is lost: both counts are already on screen. The Services census
    /// line reads "1 service running · 5 unmanaged" directly underneath, the
    /// agents' awaiting-reply count is the number the menu-bar item itself
    /// carries, and both are restated in their own sections.
    /// One refresh control, and it re-evidences for real.
    ///
    /// The button this replaces sent `.snapshot`, which the controller answers
    /// out of its own memory without sampling anything — and the popover is
    /// already handed that exact state by its subscription every supervisor
    /// tick. So it could not change a single thing on screen. Services,
    /// unmanaged processes and agent sessions are rebuilt only inside the
    /// reconciliation sweep, which is what `reEvidence()` now asks for.
    ///
    /// It also reports that it ran. A refresh that finishes in 200 ms and finds
    /// nothing new is indistinguishable from a dead button unless it says so.
    @ViewBuilder
    private func reEvidenceButton(help: String) -> some View {
        if model.isReconciling {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                .frame(width: FleetMetrics.iconButtonSize, height: FleetMetrics.iconButtonSize)
        } else {
            IconButton(symbol: "arrow.clockwise", help: help) { model.reEvidence() }
        }
    }

    private func badgeLabel(for tab: Tab) -> String {
        switch tab {
        case .services:
            return "Services"
        case .agents:
            return "Agents"
        case .processes:
            // No count. "Processes 641" is the same number on every machine at
            // every moment — it is the size of the process table, not something
            // you would act on, and the menu-bar rule about counts applies here
            // too. The states worth a number are named in the section's own
            // census line instead.
            return tab.rawValue
        case .connections:
            return tab.menuTitle
        }
    }
}
