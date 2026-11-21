import SwiftUI
import FleetCore

enum InspectorTarget: Equatable {
    case none
    case process(Int32)
    case volume(String)
    case service(String)
    case unmanaged(String)
    case device(String)
}

enum ConsoleCommand {
    static let focusSearch = Notification.Name("com.fleetconsole.console.focusSearch")
    static let refresh = Notification.Name("com.fleetconsole.console.refresh")
    static let selectModule = Notification.Name("com.fleetconsole.console.selectModule")
    static let showHome = Notification.Name("com.fleetconsole.console.showHome")
    static let toggleTool = Notification.Name("com.fleetconsole.console.toggleTool")
    static let toggleInspector = Notification.Name("com.fleetconsole.console.toggleInspector")
    static let toggleSidebar = Notification.Name("com.fleetconsole.console.toggleSidebar")
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
    var selectedDeviceID = "self"

    var atHome = false

    var module: ConsoleModule = .overview
    var overviewFocus: OverviewFocus = .both
    var overviewTimeWindow: ChartTimeWindow = .minutes2
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

    var search = ""

    var sidebarRevealed = false

    func toggleSidebar() { sidebarRevealed.toggle() }

    var inspectorRevealed = false
    var inspectorVisible = false

    var isLiveResizing = false

    var selectedPID: Int32?
    var selectedVolumeID: String?
    var selectedSegmentID: String?
    var selectedServiceID: String?
    var selectedUnmanagedID: String?

    var processScope: ProcessScope = .all

    enum ProcessScope: String, CaseIterable, Identifiable {
        case all = "All"
        case managed = "Managed"
        case listening = "Listening"
        case heavyweight = "Heavyweight"

        var id: String { rawValue }

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

    var searchPrompt: String {
        guard isLocalDeviceSelected else { return "Local only" }
        guard !atHome else { return "Search findings" }
        switch effectiveModule {
        case .overview: return "Search activity or folders"
        case .processes: return "Search processes"
        case .storage: return "Search volumes"
        case .services: return operationsSection == "Agents" ? "Search owners, services, sessions" : "Search services"
        case .events: return "Search events"
        case .plists: return "Search jobs"
        }
    }

    var inspectorHint: String {
        guard isLocalDeviceSelected else {
            return "Select a fleet node to inspect its link and addressing."
        }
        if atHome {
            return "Select a process or managed service to inspect it here."
        }
        switch effectiveModule {
        case .overview: return "Select an agent, project or process in the activity map."
        case .processes: return "Select a process to see its tree, threads, ports and owner."
        case .storage: return "Select a segment or volume for capacity and snapshot detail."
        case .services: return "Select a service for evidence, lease, placement and logs."
        case .events: return "The event log has no per-row inspector — every fact is already inline."
        case .plists: return "Select a launch entry to inspect its plist keys and load status."
        }
    }

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

    func openOperationsSection(_ section: String) {
        let changing = module != .services || operationsSection != section || atHome || !isLocalDeviceSelected
        open(.services)
        operationsSection = section
        if changing { search = "" }
    }

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
        if let device = model.deviceRows.first(where: { item.id == "device-" + $0.id }) {
            selectedDeviceID = device.id
            atHome = false
            return
        }
        open(.events)
    }

    func inspectorTarget() -> InspectorTarget {
        guard isLocalDeviceSelected else { return .device(selectedDeviceID) }
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

    func selectVolume(_ id: String?) {
        selectedVolumeID = id
        selectedSegmentID = nil
    }

    func selectSegment(_ id: String?) {
        selectedSegmentID = id
        selectedVolumeID = nil
    }

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
        if let id = selectedSegmentID, model.breakdown.breakdown.scannedAt != nil,
           !model.breakdown.breakdown.segments.contains(where: { $0.id == id }) {
            selectedSegmentID = nil
        }
        if selectedDeviceID != "self",
           !model.deviceRows.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = "self"
        }
    }

    @discardableResult
    func handleEscape() -> Bool {
        if !search.isEmpty { search = ""; return true }
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

    func refresh(model: AppModel) {
        model.refreshAll()
        model.processes.sample()
        model.breakdown.refreshVolumes()
        model.system.sample()
        model.storage.rescan()
        model.hosts.probe(devices: model.deviceRows.map(\.record))
    }
}
