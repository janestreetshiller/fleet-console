import SwiftUI
import FleetCore

// Console navigation state — one object that owns what the three columns show.
//
// `AppModel` owns *data*; this owns *where you are*. The distinction matters
// for the same reason rows observe their own record: a search keystroke should
// not invalidate the daemon snapshot, and a snapshot should never move your
// selection.

// The module list itself is a design declaration — `ConsoleMetrics` sizes the
// toolbar picker from `allCases.count` — so it lives in `Design/ConsoleModule.swift`.

/// What the inspector column is looking at. Derived from module + selection,
/// never set independently — the inspector is a *view of* a selection, and a
/// selection that lives in two places is a selection that desynchronises.
enum InspectorTarget: Equatable {
    case none
    case process(Int32)
    /// `VolumeInfo.id` (a mount path) or a `BreakdownSegment.id` (a
    /// `StorageCategory`). One inspector resolves both, because a bar segment
    /// and a volume are two views of the same disk.
    case volume(String)
    case service(String)         // ServiceRecord.id
    case unmanaged(String)       // UnmanagedProcess.id
    case device(String)          // DeviceRecord.id
}

/// Menu-bar and keyboard commands reach the window through these. The main
/// menu is AppKit (the app bootstraps with AppKit for the status items), so
/// `CommandGroup` does not apply; notifications are the honest bridge.
///
/// `showHome` is also the welcome window's exit — its "Open Console" button
/// lands on Home, the one place that can honestly say "start here".
enum ConsoleCommand {
    static let focusSearch = Notification.Name("com.fleetconsole.console.focusSearch")
    static let refresh = Notification.Name("com.fleetconsole.console.refresh")
    static let selectModule = Notification.Name("com.fleetconsole.console.selectModule")
    static let showHome = Notification.Name("com.fleetconsole.console.showHome")
    static let toggleTool = Notification.Name("com.fleetconsole.console.toggleTool")
    static let toggleInspector = Notification.Name("com.fleetconsole.console.toggleInspector")
    static let toggleSidebar = Notification.Name("com.fleetconsole.console.toggleSidebar")
    /// Runs a command line in the window's terminal panel. Carries
    /// `userInfoCommand`, `userInfoDirectory` and `userInfoSubject`.
    static let investigate = Notification.Name("com.fleetconsole.console.investigate")
    static let runInTerminal = Notification.Name("com.fleetconsole.console.runInTerminal")
    static let userInfoModule = "module"
    static let userInfoTool = "tool"
    static let userInfoAgentRequest = "agentRequest"
    static let userInfoCommand = "command"
    static let userInfoDirectory = "directory"
    static let userInfoSubject = "subject"
}

@Observable
@MainActor
final class ConsoleModel {
    /// "self" or a `DeviceRecord.id`. The first column's selection.
    var selectedDeviceID = "self"

    /// Home is a *destination*, not another module: the module indices and
    /// their ⌘1…⌘n equivalents stay exactly where they were, and every
    /// inspector that switches exhaustively over `ConsoleModule` keeps
    /// compiling. The window opens on Overview. `module` still remembers where
    /// you were, so leaving home and coming back does not reset it.
    var atHome = false

    /// The active module for the selected device.
    var module: ConsoleModule = .overview
    /// Overview controls belong to the window ribbon, not a second row inside
    /// the module. Window-scoped state keeps those controls and the charts in
    /// sync while preserving the selection across navigation.
    var overviewFocus: OverviewFocus = .both
    var overviewTimeWindow: ChartTimeWindow = .minutes2
    /// The process module's presentation belongs to window navigation state so
    /// its selector can live in the native toolbar instead of spending a second
    /// horizontal band inside the module. Keeping it here also preserves the
    /// choice while someone checks another module and returns.
    var processView: ProcessView = .relationships
    var operationsSection = "Services"
    private var effectiveModule: ConsoleModule {
        guard module == .services else { return module }
        switch operationsSection {
        case "Storage": return .storage
        case "Events": return .events
        case "Launch Services": return .plists
        default: return .services
        }
    }

    /// Toolbar search. Applies to the module in view — processes, services and
    /// events each decide what fields it matches.
    var search = ""

    /// The local console uses the full viewport. Device navigation remains
    /// available through the native sidebar toggle.
    var sidebarRevealed = false

    func toggleSidebar() { sidebarRevealed.toggle() }

    /// Whether the inspector column is wanted. The leading sidebar has had a
    /// toggle since the toolbar bridged onto NSToolbar — AppKit supplies it —
    /// but the trailing column had none, so the one column that is a *view of
    /// your selection* could only be taken away by the window getting narrow.
    /// That is a layout accident standing in for a control. This is the intent;
    /// width can still overrule it, never the other way round.
    var inspectorRevealed = false
    /// Actual visibility, published by the root layout for the titlebar control.
    var inspectorVisible = false

    /// True for the duration of a window-edge drag.
    ///
    /// Every animated dimension in this window is a function of the content
    /// width — the two side columns, the module column, every treemap tile's
    /// rectangle — and those animations exist for *discrete* causes: a column
    /// toggled, a tool panel revealed, a squarified map reordering because a
    /// process grew. A drag is not a discrete cause. It is sixty new target
    /// values a second, each one restarting a spring that was still settling
    /// toward the last, so the layout lags behind the pointer, keeps catching
    /// up, and never arrives while you are still dragging.
    ///
    /// That is what made resizing feel springy and chewy rather than direct.
    /// AppKit already knows when a drag is in progress and says so through
    /// `windowWillStartLiveResize` / `windowDidEndLiveResize`; this carries that
    /// answer into SwiftUI, where `\.isLiveResizing` suppresses layout animation
    /// for the length of the gesture. Nothing about the *resting* animations
    /// changes — open the inspector and the columns still slide.
    var isLiveResizing = false

    /// Selection state, one per module, so switching modules never loses your
    /// place — the behaviour Finder and Music both have.
    var selectedPID: Int32?
    var selectedVolumeID: String?
    /// The storage module's *other* selection: a breakdown segment (bar stripe
    /// or legend chip). Kept apart from `selectedVolumeID` because the two are
    /// reconciled against different lists — volume ids are mount paths, segment
    /// ids are `StorageCategory` values — and validating a segment against the
    /// mount table cleared it on the next process sample.
    var selectedSegmentID: String?
    var selectedServiceID: String?
    var selectedUnmanagedID: String?

    /// Process-list scope filter.
    var processScope: ProcessScope = .all

    enum ProcessScope: String, CaseIterable, Identifiable {
        case all = "All"
        case managed = "Managed"
        case listening = "Listening"
        case heavyweight = "Heavyweight"

        var id: String { rawValue }

        /// The scope filter is the "advanced heatmap filters" premium feature:
        /// the process table's own filter is also the heatmap's, because the
        /// heatmap is drawn from the filtered rows. `all` — the unfiltered
        /// view — is free; everything that narrows it is not.
        var isPremium: Bool { self != .all }
    }

    enum ProcessView: String, CaseIterable, Identifiable {
        case relationships = "Relationships"
        case table = "Table"
        case heatmap = "Heatmap"
        case scatter = "Scatter"

        var id: String { rawValue }
    }

    enum OverviewFocus: String, CaseIterable, Identifiable {
        case both = "CPU & Memory"
        case cpu = "CPU"
        case memory = "Memory"

        var id: String { rawValue }
    }

    var isLocalDeviceSelected: Bool { selectedDeviceID == "self" }

    // MARK: - Chrome copy
    //
    // The search placeholder and the inspector's empty hint both describe *the
    // surface you are on*, so they are derived here, once, from the state that
    // decides it. They used to be written twice — `RootView.searchPrompt` and
    // `InspectorPanel.prompt` held two copies of the same switch — and only the
    // inspector's was ever on screen, because the search field bridges into the
    // toolbar from that column. Editing the other one changed nothing, silently.
    // Same failure the toolbox exists to prevent, in prose instead of colour.

    /// The search field's placeholder. No trailing ellipsis: macOS reserves that
    /// for a control that opens something needing more input, and in a
    /// placeholder it reads as a hint that was itself truncated.
    var searchPrompt: String {
        guard isLocalDeviceSelected else { return "Local only" }
        guard !atHome else { return "Search processes" }
        switch effectiveModule {
        case .overview: return "Search processes"
        case .processes: return "Search processes"
        case .storage: return "Search volumes"
        case .services: return "Search services"
        case .events: return "Search events"
        case .plists: return "Search jobs"
        }
    }

    /// What the inspector says when nothing is selected. Home is handled first:
    /// it is not a module, so falling through to `module` here described whatever
    /// surface you had visited last — the inspector offered to inspect "a launch
    /// entry" while Home was on screen.
    var inspectorHint: String {
        guard isLocalDeviceSelected else {
            return "Select a fleet node to inspect its link and addressing."
        }
        if atHome {
            return "Select a process or managed service to inspect it here."
        }
        switch effectiveModule {
        case .overview: return "Select a process or managed service to inspect it without leaving the console."
        case .processes: return "Select a process to see its tree, threads, ports and owner."
        case .storage: return "Select a segment or volume for capacity and snapshot detail."
        case .services: return "Select a service for evidence, lease, placement and logs."
        case .events: return "The event log has no per-row inspector — every fact is already inline."
        case .plists: return "Select a launch entry to inspect its plist keys and load status."
        }
    }

    // MARK: - Destinations
    //
    // Home is what needs attention; a module is a specific process. Navigation
    // is therefore one-way work: home hands you off to a module with the row
    // already selected, and the module keeps that selection when you come back.

    func goHome() {
        if !atHome || !isLocalDeviceSelected { search = "" }
        selectedDeviceID = "self"
        atHome = true
    }

    func open(_ module: ConsoleModule) {
        if self.module != module || atHome || !isLocalDeviceSelected { search = "" }
        if !isLocalDeviceSelected { selectedDeviceID = "self" }
        self.module = module
        atHome = false
    }

    /// Drill down from a priority row to the surface that can act on it. The
    /// daemon's `AttentionItem` already says what it is about, so the routing
    /// reads that rather than re-deriving priority from the raw records.
    func reveal(_ item: AttentionItem, model: AppModel) {
        if let id = item.serviceID {
            selectedUnmanagedID = nil
            selectedServiceID = id
            open(.services)
            return
        }
        if let id = item.unmanagedID {
            selectedServiceID = nil
            selectedUnmanagedID = id
            open(.services)
            return
        }
        // Device items carry no id field of their own; match by the id the
        // controller builds rather than parsing the string, so a change to that
        // format fails to match instead of selecting the wrong node.
        if let device = model.deviceRows.first(where: { item.id == "device-" + $0.id }) {
            selectedDeviceID = device.id
            atHome = false
            return
        }
        // Controller-level items — a crash loop in fleetd itself — have no row
        // anywhere, because the controller restarting leaves no service behind.
        // The append-only log is the only place that fact is evidenced.
        open(.events)
    }

    // MARK: - Inspector routing

    func inspectorTarget() -> InspectorTarget {
        guard isLocalDeviceSelected else { return .device(selectedDeviceID) }
        // Home borrows the inspector for whatever its selected priority row is
        // about, so reading an attention item does not cost a navigation.
        if atHome || module == .overview {
            if let pid = selectedPID { return .process(pid) }
            if let id = selectedServiceID { return .service(id) }
            if let id = selectedUnmanagedID { return .unmanaged(id) }
            return .none
        }
        switch effectiveModule {
        case .overview, .events, .plists:
            return .none
        case .processes:
            return selectedPID.map { .process($0) } ?? .none
        case .storage:
            if let id = selectedVolumeID { return .volume(id) }
            if let id = selectedSegmentID { return .volume(id) }
            return .none
        case .services:
            if let id = selectedServiceID { return .service(id) }
            if let id = selectedUnmanagedID { return .unmanaged(id) }
            return .none
        }
    }

    /// Compact work rows inspect in place rather than sending the user to
    /// another module. Clear competing selection so the target is unambiguous.
    func inspectConsoleProcess(_ pid: Int32) {
        open(.overview)
        selectedServiceID = nil
        selectedUnmanagedID = nil
        selectedPID = pid
        inspectorRevealed = true
    }

    func inspectConsoleService(_ id: String) {
        open(.overview)
        selectedPID = nil
        selectedUnmanagedID = nil
        selectedServiceID = id
        inspectorRevealed = true
    }

    // MARK: - Storage selection
    //
    // Two kinds of selection, one inspector. Setting either clears the other —
    // the inspector shows one thing, and a stale pair would decide which by
    // accident of evaluation order.

    func selectVolume(_ id: String?) {
        selectedVolumeID = id
        selectedSegmentID = nil
    }

    func selectSegment(_ id: String?) {
        selectedSegmentID = id
        selectedVolumeID = nil
    }

    // MARK: - Selection hygiene
    //
    // Live data deletes things: a process exits, a service stops, a volume
    // unmounts. A selection pointing at a dead row must clear itself or the
    // inspector renders a ghost. Called from the root view's onChange handlers.

    func reconcileSelection(model: AppModel) {
        if let pid = selectedPID, model.processes.row(pid) == nil {
            selectedPID = nil
        }
        if let id = selectedServiceID, model.service(id: id) == nil {
            selectedServiceID = nil
        }
        if let id = selectedUnmanagedID, !model.unmanaged.contains(where: { $0.id == id }) {
            selectedUnmanagedID = nil
        }
        if let id = selectedVolumeID, !model.breakdown.volumes.contains(where: { $0.id == id }) {
            selectedVolumeID = nil
        }
        // A segment is only stale once the breakdown has actually been scanned;
        // before that the segment list is empty and a selection made from a
        // previous scan's bar would be cleared for no reason.
        if let id = selectedSegmentID, model.breakdown.breakdown.scannedAt != nil,
           !model.breakdown.breakdown.segments.contains(where: { $0.id == id }) {
            selectedSegmentID = nil
        }
        if selectedDeviceID != "self",
           !model.deviceRows.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = "self"
        }
    }

    /// What the Esc key does, in order: clear search, then clear the module
    /// selection. Returns false when there was nothing to clear.
    @discardableResult
    func handleEscape() -> Bool {
        if !search.isEmpty { search = ""; return true }
        // Home's rows navigate rather than select, so there is nothing of its
        // own to clear — clearing the module's selection here would silently
        // undo a choice you cannot see.
        if atHome || module == .overview {
            guard selectedPID != nil || selectedServiceID != nil || selectedUnmanagedID != nil else { return false }
            selectedPID = nil; selectedServiceID = nil; selectedUnmanagedID = nil
            return true
        }
        switch effectiveModule {
        case .processes where selectedPID != nil: selectedPID = nil; return true
        case .storage where selectedVolumeID != nil || selectedSegmentID != nil:
            selectedVolumeID = nil; selectedSegmentID = nil; return true
        case .services where selectedServiceID != nil || selectedUnmanagedID != nil:
            selectedServiceID = nil; selectedUnmanagedID = nil; return true
        case .plists: return false
        default: return false
        }
    }

    // MARK: - Refresh

    /// The one place ⌘R and the toolbar button both call: everything the
    /// window shows, re-evidenced now.
    /// Everything the window can re-measure, because that is what the button says.
    ///
    /// The storage scan and the host probe were missing. Both are deliberately off
    /// the sampling timer — walking cache trees and ssh-probing every device costs
    /// real I/O, and a monitor that thrashes the disk to report disk usage is its
    /// own bug — but "not on a timer" was silently implemented as "not on demand
    /// either". `StorageScanner.rescan()` had no caller outside its own module,
    /// which ran it once on first appearance; every ⌘R after that left the Storage
    /// figures frozen at whatever they were the first time the module was opened.
    /// An explicit refresh *is* the on-demand case those probes were built for.
    func refresh(model: AppModel) {
        model.refreshAll()
        model.processes.sample()
        model.breakdown.refreshVolumes()
        model.system.sample()
        model.storage.rescan()
        model.hosts.probe(devices: model.deviceRows.map(\.record))
    }
}
