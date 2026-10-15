import AppKit
import SwiftUI
import FleetCore

// The console window: native chrome for a SwiftUI content tree.
//
// The app bootstraps with AppKit (status items, single-instance handoff,
// SMAppService), so the window is built here rather than in a `WindowGroup`
// scene. Everything the scene API would configure is set explicitly:
//
//   * `.fullSizeContentView` + hidden title → the unified look, where the
//     toolbar and content share one surface (Safari, Freeform, Xcode).
//   * `.unifiedCompact` toolbar style → the compact inline bar. SwiftUI's
//     `.toolbar` content in `RootView` bridges onto the window's NSToolbar,
//     including the automatic sidebar toggle.
//   * A titlebar accessory carries the controller connection status, so the
//     one fact that changes what every number means is visible on every screen
//     without spending content-column space on it.

@MainActor
final class ConsoleWindowController {
    private(set) var window: NSWindow?

    private let model: AppModel
    /// Internal rather than private so `SurfaceRenderer` can drive the module
    /// and selection while capturing the window. Nothing in the app writes it
    /// from outside — navigation still goes through `ConsoleCommand`.
    let console = ConsoleModel()
    /// Held here, not in a view: the tool surfaces own child processes, and a
    /// terminal must outlive every SwiftUI rebuild of the tree that shows it.
    let tools = ChromeTools()

    /// Appended on the main thread when the window is built, released in `deinit`.
    /// `deinit` is nonisolated in Swift 6 and the tokens are not Sendable, so the
    /// access is spelled out as unchecked.
    private nonisolated(unsafe) var navigationObservers: [NSObjectProtocol] = []
    /// `NSWindow.delegate` is a weak reference, so the observer has to be owned
    /// somewhere that outlives the window's construction or it deallocates on
    /// the way out of `show()` and the window quietly has no delegate again.
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

    /// The two commands that say *where to be* are observed here, in AppKit, at
    /// init — not in `ConsoleRootView` alongside the rest.
    ///
    /// Every `ConsoleCommand` sender calls `openConsole()` and then posts, in the
    /// same turn. When the window is already up that is fine, and it was always
    /// fine in practice, because the only senders were ⌘-equivalents in the main
    /// menu and an `.accessory` app's main menu is live only while the app is
    /// active — which meant the window existed. The status item's dropdown is
    /// live with no window at all, so choosing **Processes** from a cold start
    /// now runs exactly the path that was never exercised: `show()` builds the
    /// hosting controller, the notification posts, and SwiftUI installs the
    /// `.onReceive` subscriptions at some later point of its own choosing. The
    /// window would have opened on Home.
    ///
    /// `console` exists from `init`, before any view does, so an observer here
    /// cannot be late. The commands that genuinely need the view — focusing the
    /// toolbar's search field, toggling a tool whose context is measured from the
    /// layout — stay in `ConsoleRootView`, and neither is reachable without a
    /// window to be late for.
    private func observeNavigationCommands() {
        let centre = NotificationCenter.default
        navigationObservers.append(centre.addObserver(forName: ConsoleCommand.investigate, object: nil, queue: .main) { [weak self] note in
            guard let starter = note.userInfo?["starter"] as? String,
                  let subject = note.userInfo?["subject"] as? String,
                  starter.utf8.count <= 17 * 1024 else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                if let block = self.model.investigationBlock { self.model.actionError = block; return }
                guard let executable = Bundle.main.resourceURL?.appendingPathComponent("bin/fleet-agent"),
                      FileManager.default.isExecutableFile(atPath: executable.path) else { return }
                self.show()
                if !self.tools.investigate(starter, executable: executable, subject: subject) {
                    self.model.actionError = "An investigation is already running. Finish it before starting another."
                }
            }
        })
        navigationObservers.append(
            centre.addObserver(forName: ConsoleCommand.selectModule, object: nil, queue: .main) {
                [console] note in
                guard let raw = note.userInfo?[ConsoleCommand.userInfoModule] as? String,
                      let module = ConsoleModule(rawValue: raw) else { return }
                MainActor.assumeIsolated { console.open(module) }
            })
        navigationObservers.append(
            centre.addObserver(forName: ConsoleCommand.showHome, object: nil, queue: .main) {
                [console] _ in
                MainActor.assumeIsolated { console.goHome() }
            })
        // A hand-off to the designated agent arrives from the popover with no
        // window up, so it is observed here for the same reason as the two above.
        navigationObservers.append(
            centre.addObserver(forName: ConsoleCommand.runInTerminal, object: nil, queue: .main) {
                [weak self] note in
                guard let command = note.userInfo?[ConsoleCommand.userInfoCommand] as? String else { return }
                let directory = (note.userInfo?[ConsoleCommand.userInfoDirectory] as? String) ?? NSHomeDirectory()
                let subject = (note.userInfo?[ConsoleCommand.userInfoSubject] as? String) ?? "Terminal"
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if !self.tools.run(command, in: ToolContext(workingDirectory: URL(fileURLWithPath: directory), subject: subject)) {
                        self.model.actionError = "Return to the shell after the investigation before starting another terminal command."
                    }
                }
            })
    }

    func show(activate: Bool = true) {
        if let window {
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
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        installInspectorToggle(on: window)
        // The titlebar remains draggable. Treating the entire live dashboard as
        // a drag region makes AppKit walk every chart/gauge path on each update.
        window.isMovableByWindowBackground = false
        // Resizes on both axes, with a floor on each and no ceiling.
        //
        // It used to be aspect-locked (`contentAspectRatio`) and capped at the
        // composed size (`contentMaxSize`), on the argument that the console is
        // "one composition at a range of sizes rather than a canvas that
        // stretches". The argument is about the *layout*, and the layout holds
        // it on its own: the side columns clamp between two rungs, the module
        // column takes the remainder, and the cards flow in an adaptive grid
        // that spends width when it has it. None of that needed the window's
        // help. What the lock actually did was make dragging the right edge
        // move the bottom edge, and make the window refuse to grow past its
        // default on a display with room to spare — two behaviours no other Mac
        // window has, on the surface you resize most.
        //
        // Both floors are derived rather than picked, because the last picked
        // one here was wrong and unfalsifiable: it was "half the composed
        // width", 780, against a column reserve of 786, so the window could be
        // dragged to a size where the columns did not fit and the module column
        // went under the width its own comment called a floor.
        // `minimumContentWidth` is one side column, the module column, the rail
        // and a tool panel's floor; `minimumContentHeight` is a module header
        // and one whole card. `ConsoleLayoutTests` asserts one point under
        // either does not fit.
        window.contentMinSize = NSSize(
            width: ConsoleLayout.minimumContentWidth.rounded(),
            height: ConsoleLayout.minimumContentHeight.rounded())
        // Full screen follows the lock. `.fullScreenNone` was set for one stated
        // reason — the window is "one composition at a range of sizes, not a
        // canvas that stretches" — and that reason was the aspect lock, which
        // is gone. Keeping the restriction and citing a constraint that no
        // longer exists is the same decay rule 9 is about, one layer under the
        // prose. The View menu gains its Full Screen item in the same change,
        // which is what rule 10 requires: the chrome and the capability move
        // together, in either direction.
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentViewController = hosting
        // Deliberately no frame autosave: a saved frame from a previous build
        // would restore a size this one does not support.
        window.isReleasedWhenClosed = false

        // No titlebar status pill. "fleetd 1.0.0 · up 1d 0h" is a version string
        // and an uptime — neither is a thing you act on, and the sidebar's own
        // footer already carries whether the controller is connected, which is
        // the part that matters. It was decoration occupying the ribbon's most
        // valuable corner.

        // The delegate exists for exactly one question: is the user dragging an
        // edge right now. Everything animated in this window is a function of
        // the content width, so without this the whole composition springs
        // after the pointer instead of tracking it. See `LiveResizeObserver`.
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
        // SwiftUI's split view can fit the window to its content's minimum on
        // first show; assert the intended default size afterwards so the
        // console never opens cramped.
        window.setContentSize(defaultContentSize)
        if activate { window.center() }
    }

    /// Reserve the right titlebar edge independently of SwiftUI toolbar ordering.
    /// The same command is used by this control and the View menu shortcut.
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

// MARK: - Live resize

/// Reports whether a window-edge drag is in progress.
///
/// AppKit has always known this — `inLiveResize` on the view, and these two
/// delegate callbacks around the gesture — and SwiftUI has no equivalent. The
/// window had no delegate at all, so the answer was there and nobody asked for
/// it, and every spring in the console ran against a width that was changing
/// sixty times a second.
///
/// A separate object rather than conformance on `ConsoleWindowController`,
/// because `NSWindowDelegate` is a wide protocol and the controller adopting it
/// would be an invitation to answer other questions here later. This one
/// answers one.
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
        // The final size lands with this callback, so clearing the flag here
        // means the last frame of the drag is unanimated too. Anything that
        // *should* animate — a column toggled while the pointer was down — is
        // keyed on its own discrete value and is unaffected.
        changed(false)
    }
}
