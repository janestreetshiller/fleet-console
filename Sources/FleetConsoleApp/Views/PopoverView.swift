import SwiftUI
import FleetCore

// The Services section of the one menu-bar popover, plus the pieces its
// neighbours share — the destructive-action alerts, the controller-down banner,
// the attention list and the local-tools list.
//
// This header used to say "Two menu-bar surfaces", name the sections Servers /
// Agents / Connections, and argue that they were "separate items because they
// answer different questions at different moments". The app has put up one
// status item with four tabs for some time. `docs/DESIGN-SYSTEM.md` names three
// comments that described the old menu bar after it was gone and says they were
// fixed; two of them were, and this was the third. The marker check it added
// reads the identifiers the app constructs, so it could not see a stale sentence
// in a source file — which is the shape of every remaining doc-rot bug in here:
// what nothing counts, drifts.

// MARK: - Services

/// The Services half of the Fleet item. Rows expand in place, so there is no
/// separate "overview vs details" mode to choose between — one less control, and
/// the actions are always one click away.
struct ServicesContent: View {
    @Bindable var model: AppModel
    var openDashboard: () -> Void

    @State private var expanded: String?
    @State private var pendingAction: DestructiveAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                verdict
                if !model.connected { ControllerDownBanner(model: model) }
                if !model.attention.isEmpty {
                    AttentionSection(model: model, expandedService: $expanded)
                }
                ServicesSection(model: model, expanded: $expanded, pendingAction: $pendingAction)
                LocalToolsSection(model: model)
                Spacer(minLength: 8)
            }
        }
        .frame(maxHeight: FleetMetrics.sectionMaxHeight)
        .destructiveActionAlert($pendingAction, model: model)
        .actionErrorAlert(model: model)
    }

    /// What this tab is actually for: whether anything needs a decision.
    ///
    /// This was four `StatTile`s — Running, Agents, Unmanaged, Attention — which
    /// is the same header the Agents and Network tabs open with, and two of the
    /// four numbers (Agents, Running) were repeated verbatim on the Agents tab.
    /// Four counters also flatten the one distinction this surface exists to
    /// draw: "3 running, 0 attention" and "0 running, 3 attention" are the same
    /// shape on screen and opposite facts. The console's Home surface already
    /// leads with the verdict and puts the counts underneath it, in those words
    /// — this is that, at popover density.
    private var verdict: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: verdictSymbol)
                .font(FleetFont.rowTitle)
                .foregroundStyle(verdictTone.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(verdictTitle)
                    .font(FleetFont.title)
                Text(census)
                    .font(FleetFont.subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, FleetMetrics.gutter)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var verdictTone: StatusTone {
        if model.criticalCount > 0 { return .bad }
        return model.attention.isEmpty ? .good : .warn
    }

    private var verdictSymbol: String {
        switch verdictTone {
        case .bad: return "exclamationmark.octagon.fill"
        case .warn: return "exclamationmark.triangle.fill"
        default: return "checkmark.circle.fill"
        }
    }

    private var verdictTitle: String {
        if model.criticalCount > 0 {
            return "\(model.criticalCount) need\(model.criticalCount == 1 ? "s" : "") a decision"
        }
        if !model.attention.isEmpty {
            return "\(model.attention.count) to look at"
        }
        return "Nothing needs a decision"
    }

    /// The counts, stated once, as a sentence rather than as a row of numerals
    /// whose labels have to be read to know which is which.
    private var census: String {
        let services = model.runningServices.count
        var parts = ["\(services) service\(services == 1 ? "" : "s") running"]
        if !model.unmanaged.isEmpty { parts.append("\(model.unmanaged.count) unmanaged") }
        return parts.joined(separator: " · ")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Needs attention", subtitle: "\(model.attention.count)")

            ForEach(model.attention.prefix(6)) { item in
                AttentionRow(item: item) {
                    expandedService = item.serviceID ?? item.unmanagedID
                }
            }

            if model.attention.count > 6 {
                Text("+ \(model.attention.count - 6) more in the dashboard")
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
