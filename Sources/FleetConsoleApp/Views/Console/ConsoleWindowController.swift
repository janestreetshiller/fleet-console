import AppKit
import SwiftUI
import FleetCore

@MainActor
final class ConsoleWindowController {
    private(set) var window: NSWindow?

    private let model: AppModel
    let console = ConsoleModel()
    let tools = ChromeTools()

    private nonisolated(unsafe) var navigationObservers: [NSObjectProtocol] = []
    private var liveResizeObserver: LiveResizeObserver?

    init(model: AppModel) {
        self.model = model
        observeNavigationCommands()
    }

    deinit {
        for observer in navigationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func observeNavigationCommands() {
        let centre = NotificationCenter.default
        navigationObservers.append(centre.addObserver(forName: ConsoleCommand.investigate, object: nil, queue: .main) { [weak self] note in
            guard let starter = note.userInfo?["starter"] as? String,
                  let subject = note.userInfo?["subject"] as? String,
                  starter.utf8.count <= 17 * 1024,
                  let request = note.object as? InvestigationRequest else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                if let block = self.model.investigationBlock { self.model.actionError = block; return }
                self.show()
                if !self.tools.investigate(starter, billing: self.model.ourosBilling, subject: subject, validation: { [weak self] in
                    guard let self, request.isFresh(at: Date()) else { return false }
                    guard request.kind == "process" else { return true }
                    guard let selected = request.processes.first, let current = self.model.processes.row(selected.pid) else { return false }
                    return !selected.startSignature.isEmpty && current.startSignature == selected.startSignature
                }) {
                    self.model.actionError = "An investigation is already running. Finish it before starting another."
                }
            }
        })
        navigationObservers.append(
            centre.addObserver(forName: ConsoleCommand.selectModule, object: nil, queue: .main) {
                [console] note in
                guard let raw = note.userInfo?[ConsoleCommand.userInfoModule] as? String,
                      let module = ConsoleModule(rawValue: raw) else { return }
                let operationsSection = note.userInfo?["operationsSection"] as? String
                MainActor.assumeIsolated {
                    if let operationsSection { console.operationsSection = operationsSection }
                    console.open(module)
                }
            })
        navigationObservers.append(
            centre.addObserver(forName: ConsoleCommand.showHome, object: nil, queue: .main) {
                [console] _ in
                MainActor.assumeIsolated { console.goHome() }
            })
        navigationObservers.append(
            centre.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) {
                [weak self] note in
                let closing = (note.object as? NSWindow).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, let closing,
                          self.window.map(ObjectIdentifier.init) == closing else { return }
                    self.tools.registry.closeTerminalSessions()
                }
            })
        navigationObservers.append(
            centre.addObserver(forName: ConsoleCommand.runInTerminal, object: nil, queue: .main) {
                [weak self] note in
                let agentRequest = note.userInfo?[ConsoleCommand.userInfoAgentRequest] as? TerminalAgentRequest
                let command = note.userInfo?[ConsoleCommand.userInfoCommand] as? String
                guard agentRequest != nil || command != nil else { return }
                let directory = (note.userInfo?[ConsoleCommand.userInfoDirectory] as? String) ?? NSHomeDirectory()
                let subject = (note.userInfo?[ConsoleCommand.userInfoSubject] as? String) ?? "Terminal"
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let agentRequest {
                        if !self.tools.startAgent(agentRequest) {
                            self.model.actionError = "Could not start the agent. Close an ended session (limit: four) and check the agent executable. The saved request was not executed: \(agentRequest.reportURL.path)"
                        }
                    } else if let command,
                              !self.tools.run(command, in: ToolContext(workingDirectory: URL(fileURLWithPath: directory), subject: subject)) {
                        self.model.actionError = "Select Shell and install tmux before starting a terminal command. Agent and read-only investigation sessions do not accept command injection."
                    }
                }
            })
    }

    func show(activate: Bool = true) {
        if let window {
            if tools.revealed == .terminal { tools.registry.resumeTerminal() }
            if activate {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFront(nil)
            }
            return
        }

        let root = ConsoleRootView(model: model, console: console, tools: tools)
        let hosting = NSHostingController(rootView: root)

        let defaultContentSize = DashboardWindowGeometry.defaultContentSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "FleetConsole"
        window.titleVisibility = .hidden
        Self.configureSceneChrome(window)
        installInspectorToggle(on: window)
        window.isMovableByWindowBackground = false
        window.contentMinSize = NSSize(
            width: ConsoleLayout.minimumContentWidth.rounded(),
            height: ConsoleLayout.minimumContentHeight.rounded())
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false

        let observer = LiveResizeObserver { [console] active in
            console.isLiveResizing = active
        }
        window.delegate = observer
        self.liveResizeObserver = observer

        self.window = window
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            window.orderFront(nil)
        }
        window.setContentSize(defaultContentSize)
        if activate { window.center() }
    }

    static func configureSceneChrome(_ window: NSWindow) {
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
    }

    private func installInspectorToggle(on window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        let hosting = NSHostingView(rootView: InspectorTitlebarControl(console: console))
        hosting.frame = NSRect(x: 0, y: 0, width: 38, height: 30)
        accessory.view = hosting
        accessory.layoutAttribute = .right
        window.addTitlebarAccessoryViewController(accessory)
    }
}

private struct InspectorTitlebarControl: View {
    @Bindable var console: ConsoleModel
    var body: some View {
        Button {
            NotificationCenter.default.post(name: ConsoleCommand.toggleInspector, object: nil)
        } label: {
            Image(systemName: "sidebar.trailing")
                .frame(width: FleetMetrics.iconButtonSize, height: FleetMetrics.iconButtonSize)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(console.inspectorVisible ? "Hide Inspector" : "Show Inspector")
        .accessibilityValue(console.inspectorVisible ? "Visible" : "Hidden")
        .help(console.inspectorVisible ? "Hide inspector (⌥⌘I)"
              : "Show inspector (⌥⌘I). Closes a tool panel if more space is needed.")
    }
}

@MainActor
final class LiveResizeObserver: NSObject, NSWindowDelegate {
    private let changed: (Bool) -> Void

    init(changed: @escaping (Bool) -> Void) {
        self.changed = changed
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        changed(true)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        changed(false)
    }
}
