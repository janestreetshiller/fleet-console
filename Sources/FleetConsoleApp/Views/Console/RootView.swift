import SwiftUI
import AppKit
import FleetCore

private struct ConsoleChrome<Bar: ToolbarContent>: ViewModifier {
    @Bindable var console: ConsoleModel
    let prompt: String
    let toolbar: Bar

    func body(content: Content) -> some View {
        content
            .navigationSplitViewStyle(.balanced)
            .toolbar { toolbar }
            .searchable(text: $console.search, placement: .toolbar, prompt: prompt)
    }
}

struct ConsoleRootView: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel
    let tools: ChromeTools

    @State private var contentWidth: CGFloat = DashboardWindowGeometry.defaultContentSize.width

    var body: some View {
        HStack(spacing: 0) {
            splitView
            inspectorColumn
            ChromeToolField(model: model, console: console, tools: tools,
                            outerWidth: contentWidth)
        }
        .animation(ConsoleAnimation.column, value: showsInspector)
        .animation(ConsoleAnimation.column, value: tools.revealed)
        .environment(\.isLiveResizing, console.isLiveResizing)
        .opaqueLiquidGlassScene()
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { contentWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in contentWidth = width }
            }
        }
        .actionErrorAlert(model: model)
        .onExitCommand { console.handleEscape() }
        .onReceive(NotificationCenter.default.publisher(for: ConsoleCommand.focusSearch)) { _ in
            Self.focusToolbarSearchField()
        }
        .onReceive(NotificationCenter.default.publisher(for: ConsoleCommand.refresh)) { _ in
            console.refresh(model: model)
        }
        .onReceive(NotificationCenter.default.publisher(for: ConsoleCommand.toggleSidebar)) { _ in
            console.toggleSidebar()
        }
        .onReceive(NotificationCenter.default.publisher(for: ConsoleCommand.toggleInspector)) { _ in
            let reveal = !showsInspector
            if inspectorBlockedByWidth && reveal { tools.dismiss() }
            console.inspectorRevealed = reveal
        }
        .onReceive(NotificationCenter.default.publisher(for: ConsoleCommand.toggleTool)) { note in
            guard let raw = note.userInfo?[ConsoleCommand.userInfoTool] as? String,
                  let tool = ConsoleTool(rawValue: raw) else { return }
            tools.toggle(tool, context: toolContext)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .init("com.fleetconsole.console.selectPID"))) { note in
            guard let pid = note.userInfo?["pid"] as? Int32 else { return }
            console.open(.processes)
            console.selectedPID = pid
        }
        .onChange(of: showsInspector, initial: true) { _, visible in
            console.inspectorVisible = visible
        }
        .onChange(of: model.lastSnapshotAt) {
            Task { @MainActor in console.reconcileSelection(model: model) }
        }
        .onChange(of: model.processes.capturedAt) {
            Task { @MainActor in console.reconcileSelection(model: model) }
        }
        .onChange(of: console.inspectorTarget()) { _, target in
            if target != .none { console.inspectorRevealed = true }
        }
        .onChange(of: console.selectedDeviceID) {
            if console.isLocalDeviceSelected { model.refreshAll() }
        }
        .onChange(of: toolContext) { _, context in tools.update(context: context) }
        .onAppear {
            tools.update(context: toolContext)
            console.refresh(model: model)
        }
    }

    private static let inspectorAndPanelFloor = ConsoleLayout.inspectorAndPanelFloor

    private var showsInspector: Bool {
        guard console.inspectorRevealed else { return false }
        return tools.revealed == nil || contentWidth >= Self.inspectorAndPanelFloor
    }

    private var inspectorBlockedByWidth: Bool {
        tools.revealed != nil && contentWidth < Self.inspectorAndPanelFloor
    }

    private var sideColumnWidth: CGFloat {
        let panel = tools.revealed == nil ? 0 : ConsoleToolMetrics.panelIdeal
        let split = max(0, contentWidth - panel)
        return ConsoleLayout.sideColumn(splitWidth: split)
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { console.sidebarRevealed ? .all : .detailOnly },
            set: { console.sidebarRevealed = $0 != .detailOnly }
        )) {
            FleetSidebarView(model: model, console: console)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            contentColumn
        }
        .modifier(ConsoleChrome(console: console, prompt: searchPrompt,
                                toolbar: toolbarContent))
    }

    @ViewBuilder
    private var inspectorColumn: some View {
        if showsInspector {
            InspectorPanel(model: model, console: console)
                .frame(width: sideColumnWidth)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(ConsoleColor.hairline)
                        .frame(width: ChromeRailMetrics.handleWidth)
                }
                .transition(.move(edge: .trailing))
                .clipped()
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        if console.isLocalDeviceSelected {
            if console.atHome {
                HomeModule(model: model, console: console)
            } else {
                switch console.module {
                case .overview: OverviewWorkspace(model: model, console: console)
                case .processes: ProcessWorkspace(model: model, console: console)
                case .storage: StorageModule(model: model, console: console)
                case .services: OperationsWorkspace(model: model, console: console)
                case .events: EventsModule(model: model, console: console)
                case .plists: PlistsModule(console: console)
                }
            }
        } else {
            DeviceDetailView(model: model, deviceID: console.selectedDeviceID)
        }
    }

    private var searchPrompt: String { console.searchPrompt }

    private var toolContext: ToolContext {
        guard console.isLocalDeviceSelected else {
            return ToolContext(subject: fleetDeviceName)
        }
        if let id = console.selectedServiceID, let record = model.service(id: id) {
            let cwd = record.cwd.isEmpty ? NSHomeDirectory() : record.cwd
            return ToolContext(workingDirectory: URL(fileURLWithPath: cwd),
                               subject: record.friendlyName, serviceID: id)
        }
        return ToolContext(subject: console.atHome ? "Home" : console.module.rawValue)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if console.isLocalDeviceSelected && !console.atHome && console.module == .processes {
            ToolbarItem(placement: .principal) {
                Picker("Process view", selection: $console.processView) {
                    ForEach(ConsoleModel.ProcessView.allCases) { view in
                        Text(view.rawValue).tag(view)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: ConsoleMetrics.processViewPickerWidth)
                .accessibilityIdentifier("process.view")
                .help("Choose how running processes are presented")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Agent awareness") { console.open(.overview) }
                Section("Detailed views") {
                    ForEach(ConsoleModule.allCases.filter { $0 != .overview }) { module in
                        Button(module.title) { console.open(module) }
                    }
                }
                Section("Tools") {
                ForEach(ConsoleTool.allCases) { tool in
                    Button {
                        tools.toggle(tool, context: toolContext)
                    } label: {
                        Label(tool.title, systemImage: tool.symbol)
                    }
                }
                }
            } label: {
                Label("Tools", systemImage: "wrench.and.screwdriver")
                    .labelStyle(.titleAndIcon)
            }
            .help("Detailed views, terminal and files")
            .accessibilityLabel("Tools")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                console.refresh(model: model)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Re-evidence everything the window shows (⌘R)")
        }

    }

    private var fleetDeviceName: String {
        model.deviceRows.first { $0.id == console.selectedDeviceID }?.record.name ?? "Device"
    }

    static func focusToolbarSearchField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
                return
            }
            if let field = findSearchField(in: window.contentView?.superview) {
                window.makeFirstResponder(field)
            }
        }
    }

    private static func findSearchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let field = view as? NSSearchField { return field }
        for subview in view.subviews {
            if let found = findSearchField(in: subview) { return found }
        }
        return nil
    }
}

struct OverviewToolbarControls: View {
    @Bindable var console: ConsoleModel

    var body: some View {
        HStack(spacing: 8) {
            Picker("Chart focus", selection: $console.overviewFocus) {
                ForEach(ConsoleModel.OverviewFocus.allCases) { focus in
                    Text(focus.rawValue).tag(focus)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("overview.focus")
            .help("Give CPU or memory the full chart width")

            Picker("Time range", selection: $console.overviewTimeWindow) {
                ForEach(ChartTimeWindow.allCases, id: \.self) { window in
                    Text(window.label).tag(window)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("overview.time")
            .help("Zoom the visible time range without averaging samples")
        }
        .controlSize(.small)
        .fixedSize()
        .accessibilityElement(children: .contain)
    }
}
