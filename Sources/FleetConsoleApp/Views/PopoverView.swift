import SwiftUI
import FleetCore

// Attention can outlive a service row or describe the controller/a device.
// Keep its explanation and dashboard handoff beside the service inventory.
struct ServicesContent: View {
    @Bindable var model: AppModel
    var openDashboard: () -> Void
    var labels: ServiceLabelsStore = .shared

    @State private var expanded: String?
    @State private var pendingAction: DestructiveAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !model.connected { ControllerDownBanner(model: model) }
                if !model.attention.isEmpty {
                    AttentionSection(model: model, expandedService: $expanded, openDashboard: openDashboard)
                }
                ServicesSection(model: model, expanded: $expanded, pendingAction: $pendingAction, labels: labels)
                LocalToolsSection(model: model)
                Spacer(minLength: 8)
            }
            .padding(.top, 4)
        }
        .frame(maxHeight: FleetMetrics.sectionMaxHeight)
        .destructiveActionAlert($pendingAction, model: model)
        .actionErrorAlert(model: model)
    }
}

// MARK: - Shared alerts

extension View {
    func destructiveActionAlert(_ action: Binding<DestructiveAction?>, model: AppModel) -> some View {
        alert(item: action) { pending in
            Alert(title: Text(pending.title),
                  message: Text(pending.message),
                  primaryButton: .destructive(Text(pending.kind.rawValue)) {
                      switch pending.kind {
                      case .stop: model.stop(pending.service)
                      case .restart: model.restart(pending.service)
                      case .kill: model.forceKill(pending.service)
                      }
                  },
                  secondaryButton: .cancel())
        }
    }

    func actionErrorAlert(model: AppModel) -> some View {
        alert("Action failed",
              isPresented: Binding(get: { model.actionError != nil },
                                   set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) { model.actionError = nil }
        } message: {
            Text(model.actionError ?? "")
        }
    }
}

// MARK: - Shared pieces

struct ControllerDownBanner: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .foregroundStyle(StatusTone.bad.ink)
                Text("Controller not running")
                    .font(FleetFont.rowTitleCompact.weight(.semibold))
            }
            if let error = model.connectionError {
                Text(error)
                    .font(FleetFont.mono(9.5))
                    .foregroundStyle(SurfaceInk.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StatusTone.bad.wash,
                    in: RoundedRectangle(cornerRadius: FleetMetrics.tileCorner, style: .continuous))
        .padding(.horizontal, FleetMetrics.rowInset)
        .padding(.top, 8)
    }
}

struct AttentionSection: View {
    @Bindable var model: AppModel
    @Binding var expandedService: String?
    var openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Needs attention", subtitle: "\(model.attention.count)")

            ForEach(model.attention.prefix(6)) { item in
                AttentionRow(item: item) {
                    if let serviceID = item.serviceID,
                       model.activeServices.contains(where: { $0.id == serviceID }) {
                        expandedService = serviceID
                    } else {
                        openDashboard()
                    }
                }
            }

            if model.attention.count > 6 {
                Button("+ \(model.attention.count - 6) more in the dashboard", action: openDashboard)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("attention.dashboard")
                    .font(FleetFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                    .padding(.horizontal, FleetMetrics.gutter)
                    .padding(.top, 2)
            }
        }
    }
}

struct AttentionRow: View {
    let item: AttentionItem
    let reveal: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: reveal) {
            FleetRowLabel(icon: Iconography.attention(item),
                          tone: item.severity == .critical ? .bad : .warn,
                          title: item.title,
                          subtitle: item.detail,
                          trailingText: Fmt.relative(item.since))
                .padding(.horizontal, FleetMetrics.rowInset)
                .padding(.vertical, FleetMetrics.rowVerticalPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("attention.\(item.id)")
        .accessibilityLabel("\(item.title). \(item.detail)")
        .onHover { hovering = $0 }
        .rowBackground(hovering: hovering)
        .padding(.horizontal, FleetMetrics.rowHighlightMargin)
    }
}


/// Your own long-running tools, declared in config.json. These are not managed by
/// the controller and never will be — but they are yours, so they get a name, a
/// port and an uptime here instead of appearing as anonymous unmanaged processes.
/// That is the point of the section: it is what the tools' own menu-bar apps were
/// telling you, in one place.
struct LocalToolsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        if !model.externalServices.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Local tools",
                              subtitle: "\(model.externalServices.filter(\.running).count) of \(model.externalServices.count) up") {
                    IconButton(symbol: "slider.horizontal.3", help: "Edit the list in config.json") {
                        model.openConfigFile()
                    }
                }
                ForEach(model.externalServices) { tool in
                    Button {
                        if let url = tool.url, tool.running { model.openURL(url) }
                    } label: {
                        FleetRowLabel(icon: tool.symbol,
                                      tone: tool.running ? .good : .neutral,
                                      title: tool.name,
                                      subtitle: tool.summary,
                                      trailingText: tool.running && tool.url != nil ? "open" : nil,
                                      inlineSubtitle: true)
                            .padding(.horizontal, FleetMetrics.rowInset)
                            .padding(.vertical, FleetMetrics.rowVerticalPadding)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, FleetMetrics.rowHighlightMargin)
                    .help(tool.commandLine ?? tool.name)
                }
            }
        }
    }
}
