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

    private var navigationObservers: [NSObjectProtocol] = []
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
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
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
        window.isMovableByWindowBackground = true
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
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // SwiftUI's split view can fit the window to its content's minimum on
        // first show; assert the intended default size afterwards so the
        // console never opens cramped.
        window.setContentSize(defaultContentSize)
        window.center()
    }

    /// The controller status pill, pinned at the trailing edge of the titlebar.
    /// Implemented as an accessory view because toolbar *items* are managed by
    /// SwiftUI once `.toolbar` bridges in; the accessory lives beside them.
    ///
    /// The fixed 168pt is the ribbon's own reserved space. It is deliberately
    /// unchanged by the tool rail: the rail lives in the content view, one layer
    /// below the titlebar container, and takes its width out of the split view
    /// instead of out of this.
    private func installTitlebarAccessory(into window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        let pill = TitlebarStatusPill(model: model)
        let hostingView = NSHostingView(rootView: pill)
        hostingView.frame = NSRect(x: 0, y: 0, width: 168, height: 24)
        accessory.view = hostingView
        accessory.layoutAttribute = .right
        window.addTitlebarAccessoryViewController(accessory)
    }
}

/// Controller connectivity, compressed to a pip and one line of evidence.
/// Reads the same fields the menu-bar tooltip does, so the window and the
/// menu bar can never tell two different stories.
private struct TitlebarStatusPill: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            StatusPip(tone: model.connected ? .good : .bad, size: 7, pulsing: model.connected)
            if let daemon = model.daemon, model.connected {
                // Truncates rather than pushing the capsule wider: a long version
                // string must not grow this pill into the toolbar items beside
                // it. Same rule everywhere in the ribbon.
                Text("fleetd \(daemon.version) · up \(Fmt.duration(daemon.uptime))")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("controller offline")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(.quaternary.opacity(0.6))
        )
        .overlay(
            Capsule().strokeBorder(ConsoleColor.hairline, lineWidth: 1)
        )
        .help(model.connected
              ? "Controller socket connected. \(model.daemon.map { "pid \($0.pid)" } ?? "")"
              : (model.connectionError ?? "fleetd is not answering"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.connected ? "Controller connected" : "Controller offline")
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
