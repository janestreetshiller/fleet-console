import SwiftUI
import AppKit
import FleetCore

// The console's root: three columns, one toolbar, one search, one tool rail.
//
//   ┌─────────────┬──────────────────────────┬─────────────┬──┐
//   │ Fleet mesh  │ Home or module (⌘1…⌘6)   │ Inspector   │▐ │
//   │ (devices)   │ priority view / detail   │ (selection) │▐ │
//   └─────────────┴──────────────────────────┴─────────────┴──┘
//                                                     tool rail ┘
//
// The toolbar is SwiftUI's `.toolbar` bridged onto the AppKit window's
// NSToolbar (unified-compact, hidden title): the module picker sits in the
// principal slot, search is the native toolbar search field, and the sidebar
// toggle is automatic. Menu commands arrive as `ConsoleCommand` notifications
// from the AppKit main menu.
//
// The tool rail is a trailing `safeAreaInset`, not an overlay — see
// `Chrome/ChromeToolRail.swift` for why that is the only arrangement that
// cannot land on the toolbar's words.

/// The window chrome the split view carries, in one place so the three-column
/// and two-column arrangements above cannot drift apart. The toolbar and the
/// search field must stay attached to the `NavigationSplitView` itself — that is
/// what bridges them onto the window's NSToolbar.
private struct ConsoleChrome<Bar: ToolbarContent>: ViewModifier {
    @Bindable var console: ConsoleModel
    let prompt: String
    let toolbar: Bar

    func body(content: Content) -> some View {
        content
            .navigationSplitViewStyle(.balanced)
            .toolbar { toolbar }
    }
}

struct ConsoleRootView: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel
    let tools: ChromeTools

    /// The window's content width, measured behind the tool field so the panel's
    /// clamp has something stable to divide up.
    ///
    /// Seeded with the composed width rather than zero. The side columns are a
    /// function of this, so a zero first frame meant `Scale.minor(-34)/2`
    /// clamping to the floor: both columns opened at 233 and the sidebar elided
    /// the device names it is sized to show, then corrected on the next layout
    /// pass. The window cannot be *narrower* than its own minimum and cannot be
    /// wider than the composed size, so the composed size is the only honest
    /// starting guess.
    @State private var contentWidth: CGFloat = DashboardWindowGeometry.defaultContentSize.width

    var body: some View {
        HStack(spacing: 0) {
            splitView
            inspectorColumn
            ChromeToolField(model: model, console: console, tools: tools,
                            outerWidth: contentWidth)
        }
        // One easing for both sides. `showsInspector` is the value that changes
        // when the inspector is toggled *or* when width takes it away, so both
        // routes animate identically instead of one sliding and one snapping.
        .animation(ConsoleAnimation.column, value: showsInspector)
        // Keyed on the *cause*, not on the measurement.
        //
        // This was `value: sideColumnWidth`, and that width is a pure function
        // of `contentWidth`, which is measured live from the window. So the one
        // gesture it fired on constantly was the one it should never have fired
        // on: dragging an edge handed a 0.34s spring a new target every frame,
        // each restarting before the last had settled, and the columns swam
        // after the pointer instead of tracking it. Revealing a tool panel is
        // the only *discrete* thing that changes this width, so it is what the
        // animation watches now — the slide is unchanged, the drag is direct.
        .animation(ConsoleAnimation.column, value: tools.revealed)
        .environment(\.isLiveResizing, console.isLiveResizing)
        .sketchSubstrate(seed: 0.11, grainSeed: 11)
        .background {
            // Measured on the full frame — the inset's own width is derived from
            // this, so reading it from inside the inset would be circular.
            GeometryReader { geometry in
                Color.clear
                    .onAppear { contentWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in contentWidth = width }
            }
        }
        .onExitCommand { console.handleEscape() }
        .onReceive(NotificationCenter.default.publisher(for: ConsoleCommand.focusSearch)) { _ in
            Self.focusToolbarSearchField()
        }
        .onReceive(NotificationCenter.default.publisher(for: ConsoleCommand.refresh)) { _ in
            console.refresh(model: model)
        }
        // showHome and selectModule are deliberately absent: they are observed in
        // ConsoleWindowController, which exists before this view does. A sender
        // opens the window and posts in the same turn, and the status item's
        // dropdown does that with no window up at all, so a subscription
        // installed on appearance is a subscription installed too late.
        .onReceive(NotificationCenter.default.publisher(for: ConsoleCommand.toggleInspector)) { _ in
            console.inspectorRevealed.toggle()
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
        // Live data deletes rows; selections pointing at ghosts clear themselves.
        // Deferred one runloop tick: these fire while SwiftUI is still pushing
        // new rows through the table's NSTableView delegate, and clearing a
        // selection bound to that table re-enters the delegate mid-pass (the
        // "reentrant operation" warning macOS will assert on).
        .onChange(of: model.lastSnapshotAt) {
            Task { @MainActor in console.reconcileSelection(model: model) }
        }
        .onChange(of: model.processes.capturedAt) {
            Task { @MainActor in console.reconcileSelection(model: model) }
        }
        .onChange(of: console.selectedDeviceID) {
            // Remote nodes have one module — their own detail. Switching back
            // to This Mac restores the last module implicitly via state.
            if console.isLocalDeviceSelected { model.refreshAll() }
        }
        // A revealed panel follows the selection: opening Files on a service and
        // then picking a different one should land in the new working directory.
        .onChange(of: toolContext) { _, context in tools.update(context: context) }
        .onAppear {
            tools.update(context: toolContext)
            console.refresh(model: model)
        }
    }

    // MARK: - The split view
    //
    // Held separately so the toolbar and the search field stay attached to the
    // `NavigationSplitView` itself — they bridge onto the window's NSToolbar
    // from here, and moving them out to the `HStack` is not the same thing.

    /// The width below which column three and a tool panel stop both fitting.
    /// Derived and asserted in `ConsoleLayout` — see `ConsoleLayoutTests`, which
    /// proves the arrangement lands exactly on the module column's floor here.
    /// This was previously summed inline from four tokens and a bare `360`, and
    /// the bare 360 was the only statement anywhere of what a module column
    /// needs.
    private static let inspectorAndPanelFloor = ConsoleLayout.inspectorAndPanelFloor

    /// Column three yields only when it has to: at the composed 1560 everything
    /// stands at once, and only a window dragged toward its floor *with a tool
    /// open* makes the inspector give way — because the module column going
    /// under `ConsoleLayout.moduleColumnMin` turns its tables into horizontal
    /// scrollbars.
    private var showsInspector: Bool {
        guard console.inspectorRevealed else { return false }
        return tools.revealed == nil || contentWidth >= Self.inspectorAndPanelFloor
    }

    /// Whether width — rather than the button — is what is hiding column three.
    /// The toggle reports this in its tooltip instead of silently doing nothing,
    /// so a button that cannot take effect says why.
    private var inspectorBlockedByWidth: Bool {
        tools.revealed != nil && contentWidth < Self.inspectorAndPanelFloor
    }

    // MARK: The butterfly
    //
    // The two side columns are one column reflected. They take the same width at
    // every window size — the golden minor section, halved, clamped to the same
    // rungs — and they open and close on the same easing, so the window breathes
    // symmetrically about its centre rather than one side snapping while the
    // other slides.
    //
    // Getting there meant taking the inspector *out* of `NavigationSplitView`.
    // It was column three of a three-column split view, and hiding it swapped
    // the whole `NavigationSplitView` for a two-column one — a different view
    // type, so SwiftUI tore down the tree and built a new one. That is why the
    // inspector appeared and vanished instantly while the sidebar slid: there
    // was no transition to animate, there was a structural replacement. It also
    // meant every toggle rebuilt the sidebar and the module column for a change
    // that concerned neither.
    //
    // The inspector is now a sibling in the same `HStack` as the tool rail,
    // which is the arrangement the rail has always used and the one thing in
    // this window that has never had a layout bug. One split view now, always
    // two columns, no structural swap — and a width that can actually animate.

    /// The resting width of either side column at the current window size.
    private var sideColumnWidth: CGFloat {
        let panel = tools.revealed == nil ? 0 : ConsoleToolMetrics.panelIdeal
        let split = max(0, contentWidth - ChromeRailMetrics.railWidth - panel)
        return ConsoleLayout.sideColumn(splitWidth: split)
    }

    private var splitView: some View {
        NavigationSplitView {
            FleetSidebarView(model: model, console: console)
                // The *exact-width* overload, not `min:ideal:max:`.
                //
                // With the three-argument form the two sides did not mirror, and
                // measuring a render is what showed it: 224pt of sidebar against
                // 275pt of inspector, from one number handed to both. SwiftUI
                // treats `ideal` on a split-view column as a preference it is
                // free to override — it holds the user's drag state and its own
                // fitting pass above your request — so the left column settled
                // near its floor while the right, an ordinary framed view, took
                // the width it was given. A mirror where one half is advisory is
                // not a mirror.
                //
                // Fixing the width costs nothing here even now that the window
                // resizes freely: the column is a ratio of the current width,
                // clamped between two rungs, so it is the arrangement rather
                // than a default the user is expected to drag away from. What
                // changed with the aspect lock is which dimensions the window
                // offers, not how the split view divides the one it has.
                .navigationSplitViewColumnWidth(sideColumnWidth)
        } detail: {
            contentColumn
        }
        .modifier(ConsoleChrome(console: console, prompt: searchPrompt,
                                toolbar: toolbarContent))
    }

    /// Column three, mirrored onto the sidebar's geometry and easing.
    ///
    /// Clipped to its frame so the panel slides out of the window edge instead
    /// of being drawn outside it during the transition, and given a leading
    /// hairline because it no longer gets the split view's own column separator.
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

    // MARK: - Content column

    @ViewBuilder
    private var contentColumn: some View {
        if console.isLocalDeviceSelected {
            if console.atHome {
                HomeModule(model: model, console: console)
            } else {
                switch console.module {
                case .overview: OverviewModule(model: model, console: console)
                case .processes: ProcessModule(model: model, console: console)
                case .storage: StorageModule(model: model, console: console)
                case .services: ServicesModule(model: model, console: console)
                case .events: EventsModule(model: model, console: console)
                case .plists: PlistsModule(console: console)
                }
            }
        } else {
            DeviceDetailView(model: model, deviceID: console.selectedDeviceID)
        }
    }

    /// Kept under ~130pt at 13pt, because the toolbar search field does not get a
    /// width — it gets whatever the toolbar has left, which on a narrower window
    /// is around 150pt of text area. The previous prompts ran 168–207pt and five
    /// of the eight clipped mid-word ("Filter what needs attent"). A hint that is
    /// cut off is worse than a short one: it reads as a rendering fault.
    ///
    /// They are also not elided. The first fix for the clipping was to shorten
    /// each prompt and end it in "…", which is the wrong punctuation twice over:
    /// macOS reserves a trailing ellipsis for a control that opens something
    /// needing more input, and putting one in a placeholder says the *hint* was
    /// abbreviated — so a field that fit perfectly still looked truncated. These
    /// are whole phrases that fit, naming the noun being searched, because the
    /// field's own magnifying glass already supplies the verb.
    private var searchPrompt: String { console.searchPrompt }

    // MARK: - Tool context
    //
    // What a chrome tool should open against. A selected service has a recorded
    // cwd — that is the whole reason `--cwd` is mandatory for agents — and
    // anything else falls back to home, never to a directory guessed from a
    // process's argv.

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

    // MARK: - Toolbar
    //
    // The ribbon. Its structure and wording are fixed: the same module
    // segments in the same order, the same device label when a remote node is
    // selected, the same refresh verb. The only thing the tool rail changes
    // about it is that its text now truncates with a tail ellipsis instead of
    // being allowed to grow into space that is no longer there.

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Leading, not centred. The module cluster is navigation — where you
        // are — and navigation belongs at the start of the ribbon, not floating
        // in the middle of it competing with the title.
        ToolbarItem(placement: .navigation) {
            if console.isLocalDeviceSelected {
                Picker("Module", selection: moduleSelection) {
                    ForEach(ConsoleModule.allCases) { module in
                        Label(module.rawValue, systemImage: module.symbol)
                            .tag(Optional(module))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // Sized to the segments, not to the slot. The principal slot is
                // whatever the toolbar has left after the search field, and at
                // the 1240pt default that is ~184pt — narrower than six
                // icon-only segments want. A `maxWidth` above that is not a cap
                // at all: the picker takes its ideal width and the toolbar
                // clips it, which sliced the sixth segment in half. Sizing the
                // picker to fit makes the segments compress instead.
                .frame(width: ConsoleMetrics.modulePickerWidth)
            } else {
                // A remote node has one module: itself. The picker yields to a
                // plain title rather than offering modules that cannot apply.
                Label(fleetDeviceName, systemImage: "desktopcomputer")
                    .font(ConsoleFont.subtitle.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
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

        // The trailing counterpart to AppKit's automatic sidebar toggle. It sits
        // at the far end of the ribbon, which is where every macOS app that has
        // an inspector puts it, and it uses the system's own inspector glyph so
        // it reads as the same control users already know.
        ToolbarItem(placement: .primaryAction) {
            Button {
                console.inspectorRevealed.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(inspectorBlockedByWidth
                  ? "The window is too narrow for the inspector and a tool panel at once — close the panel or widen the window"
                  : (console.inspectorRevealed
                     ? "Hide the inspector (⌥⌘I)"
                     : "Show the inspector (⌥⌘I)"))
        }
    }

    /// Home is a destination, not another segment: the picker keeps only the
    /// modules and simply shows none of them selected while home is on screen,
    /// which is the truth. Picking a segment leaves home.
    private var moduleSelection: Binding<ConsoleModule?> {
        Binding {
            console.atHome ? nil : console.module
        } set: { selected in
            guard let selected else { return }
            console.open(selected)
        }
    }

    private var fleetDeviceName: String {
        model.deviceRows.first { $0.id == console.selectedDeviceID }?.record.name ?? "Device"
    }

    // MARK: - Search focus (⌘K)
    //
    // `.searchFocused` is macOS 15; this app targets 14. The toolbar search
    // field is a real NSSearchField once SwiftUI bridges the toolbar onto the
    // AppKit window, so focusing it is a first-responder call away — found
    // recursively rather than by toolbar-item index, which SwiftUI does not
    // promise to keep stable.

    static func focusToolbarSearchField() {
        // A beat after the menu command: the window may have been ordered in
        // by the same click, and the field must exist before it can take focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
                return
            }
            if let field = findSearchField(in: window.contentView) {
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
