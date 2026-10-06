import AppKit
import SwiftUI
import ServiceManagement
import FleetCore

// FleetConsole — one menu-bar control over one controller.
//
//   ▣ Fleet — services, agents, and connections in one popover.
//
// One status item keeps one app represented by one persistent mark. Its popover
// carries the operational and network surfaces as tabs.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Sent by a second launch to the instance that is already running.
    static let openDashboardNotification = Notification.Name("com.fleetconsole.openDashboard")

    private let model = AppModel()
    private var fleetItem: MenuBarItemController!
    private var consoleWindow: ConsoleWindowController?
    private var welcomeWindow: WelcomeWindowController?
    private var taskComposer: TaskComposerWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One instance, two items. Without this guard a second launch adds another
        // set of icons to the menu bar and another subscription to the controller,
        // and the copies are indistinguishable to anyone looking at the menu bar.
        if handOffToRunningInstance() { return }

        // The main menu: ⌘K/⌘R/⌘1…⌘6 and the standard Edit items that make
        // text fields behave. Commands route to the console window via
        // ConsoleCommand notifications; with no window open they are no-ops.
        MainMenu.install { [weak self] in self?.showDashboard() }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showDashboard),
            name: Self.openDashboardNotification, object: nil)

        Notifier.requestAuthorizationIfNeeded()

        fleetItem = MenuBarItemController(
            identifier: "fleet",
            contentView: FleetPopover(model: model,
                                      openDashboard: { [weak self] in self?.showDashboard() }),
            summary: { [model] in
                MenuBarItemController.Summary(
                    // One geometric monogram at every state. The count carries
                    // urgency without changing the app's silhouette.
                    glyph: .wordmark,
                    text: model.fleetText,
                    tint: model.fleetTint,
                    tooltip: model.fleetTooltip,
                    accessibilityLabel: "FleetConsole fleet — "
                        + model.fleetTooltip.replacingOccurrences(of: "\n", with: ", "))
            },
            menu: { [weak self] in self?.contextMenu() ?? NSMenu() },
            onWillOpen: { [model] in
                model.refreshAll()
                model.markMessagesSeen()
            })

        registerHelperIfPossible()
        observeModel()
        showWelcomeIfDue()

        if CommandLine.arguments.contains("--dashboard")
            || ProcessInfo.processInfo.environment["FLEETCONSOLE_DASHBOARD"] == "1" {
            showDashboard()
        }
    }

    /// The welcome shows once, on the first launch that was not handed off to
    /// a running instance. `consumePending()` marks it as shown in the same
    /// read, so a `--dashboard` first launch still counts — burying the
    /// welcome because the console opened headless would be the app skipping
    /// its own onboarding.
    ///
    /// The *skip* preference is premium-gated at render: the setting can be
    /// toggled only where the license allows (see WelcomeView), and it is
    /// honoured here without re-checking the licence, so downgrading cannot
    /// resurrect the window.
    private func showWelcomeIfDue() {
        guard WelcomeState.consumePending(),
              !UserDefaults.standard.bool(forKey: "fleetconsole.skipWelcome") else { return }
        let welcome = WelcomeWindowController(model: model)
        welcome.show()
        welcomeWindow = welcome
    }

    func applicationWillTerminate(_ notification: Notification) {
        DaemonClient.shared.stop()
    }

    /// If FleetConsole is already running, hand this launch's intent to it and quit.
    private func handOffToRunningInstance() -> Bool {
        let identifier = Bundle.main.bundleIdentifier ?? "com.fleetconsole.app"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let existing = others.first else { return false }

        FleetLog.info("FleetConsole is already running (pid \(existing.processIdentifier)); handing off")
        if CommandLine.arguments.contains("--dashboard")
            || ProcessInfo.processInfo.environment["FLEETCONSOLE_DASHBOARD"] == "1" {
            DistributedNotificationCenter.default().postNotificationName(
                Self.openDashboardNotification, object: nil, userInfo: nil, deliverImmediately: true)
        }
        existing.activate()
        NSApp.terminate(nil)
        return true
    }

    /// One tracking loop drives both items; the 1 Hz lease clock is deliberately
    /// not read here, so countdowns never cause a menu-bar redraw.
    private func observeModel() {
        withObservationTracking {
            _ = model.fleetGlyph
            _ = model.fleetText
            _ = model.fleetTint
            _ = model.fleetTooltip
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.fleetItem?.refresh()
                self?.observeModel()
            }
        }
    }

    /// The status item's dropdown — right-click, or ⌃-click, on the menu-bar item.
    ///
    /// Three things were wrong with the previous version and all three were the
    /// same mistake, which is a menu describing something the app does not do.
    ///
    /// **Key equivalents that were not bound anywhere.** `Open Dashboard…` drew
    /// ⌘D and `Run Reconciliation Sweep` drew ⌘R, and nothing registered either
    /// one — a status-item menu's equivalents are live only while that menu is
    /// open, and the app's real binding for the dashboard is ⌘0 in the View menu.
    /// So the dropdown advertised a second, non-working shortcut for a command
    /// that already had a working one, and a ⌘R that collides on sight with
    /// View → Refresh. Rule 10 with the window swapped for the menu bar: a
    /// shortcut you can read and cannot press is worse than no shortcut.
    ///
    /// **Ellipses on commands that complete immediately.** macOS reserves the
    /// ellipsis for a command that needs more input before it can finish.
    /// Opening a window and opening a file in your editor both complete on the
    /// click, so neither gets one. The two destructive service actions in the
    /// popover keep theirs, because those really do raise a confirmation.
    ///
    /// **No route to what the app is for.** The dropdown listed maintenance
    /// verbs and no destinations, so reaching the process table from the menu
    /// bar meant opening the dashboard and then navigating. The modules are now
    /// listed directly, generated from `ConsoleModule.allCases` by the same
    /// builder the View menu uses.
    ///
    /// Grouping is `NSMenuItem.sectionHeader`, which is AppKit's own inline
    /// header — it draws the system's small-caps grey label and carries its own
    /// spacing, so a separator either side of it would be double-ruling.
    private func contextMenu() -> NSMenu {
        let menu = NSMenu()

        let dashboard = NSMenuItem(title: "Open Dashboard",
                                   action: #selector(showDashboard), keyEquivalent: "0")
        dashboard.keyEquivalentModifierMask = [.command]
        dashboard.target = self
        menu.addItem(dashboard)

        menu.addItem(.sectionHeader(title: "Dashboard"))
        for item in MainMenu.moduleItems() { menu.addItem(item) }

        menu.addItem(.sectionHeader(title: "Fleet"))
        let newTask = NSMenuItem(title: "New Task…", action: #selector(showNewTask), keyEquivalent: "n")
        newTask.keyEquivalentModifierMask = [.command]
        newTask.target = self
        menu.addItem(newTask)
        let network = NSMenuItem(title: FleetSection.connections.menuTitle,
                                 action: #selector(showNetwork), keyEquivalent: "")
        network.target = self
        menu.addItem(network)
        let reconcile = NSMenuItem(title: "Run Reconciliation Sweep",
                                   action: #selector(self.reconcile), keyEquivalent: "")
        reconcile.target = self
        menu.addItem(reconcile)

        menu.addItem(.separator())
        let config = NSMenuItem(title: "Edit Configuration",
                                action: #selector(openConfig), keyEquivalent: "")
        config.target = self
        menu.addItem(config)
        let logs = NSMenuItem(title: "Reveal Logs in Finder",
                              action: #selector(revealLogs), keyEquivalent: "")
        logs.target = self
        menu.addItem(logs)
        // The welcome is shown once; this is the way back for a support call
        // or a fresh look — re-marking it unseen and presenting it now.
        let welcome = NSMenuItem(title: "Replay Welcome",
                                 action: #selector(replayWelcome), keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit FleetConsole",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    /// Network is a popover section, not a console module, so it opens the
    /// popover rather than the window. Naming the section on the model and then
    /// showing the popover keeps the two paths — clicking the item and choosing
    /// this — landing on one surface instead of two.
    @objc private func showNetwork() {
        model.requestedSection = .connections
        fleetItem?.showPopover()
    }

    /// Opens the Task Composer: compose a task and hand it to the controller.
    @objc private func showNewTask() {
        let composer = TaskComposerWindowController(agentProfiles: model.agentProfiles)
        taskComposer = composer
        composer.show()
    }

    @objc private func reconcile() { model.reconcileNow() }
    @objc private func openConfig() { model.openConfigFile() }
    @objc private func revealLogs() { model.revealInFinder(FleetPaths.logs.path) }

    /// Replays the first-launch welcome. Resets the once-flag *and* honours
    /// the premium skip preference — replaying is an explicit ask, so the skip
    /// setting does not apply to it (it governs launches, not requests).
    @objc private func replayWelcome() {
        WelcomeState.reset()
        let welcome = WelcomeWindowController(model: model)
        welcome.show()
        welcomeWindow = welcome
    }

    @objc func showDashboard() {
        fleetItem?.closePopover()
        if consoleWindow == nil {
            consoleWindow = ConsoleWindowController(model: model)
        }
        consoleWindow?.show()
    }

    // MARK: - Service management
    //
    // The controller is a launchd user agent registered through SMAppService.
    // launchd — not this app — keeps it alive, so leases keep expiring and leaked
    // processes keep being reaped with the UI closed.

    private func registerHelperIfPossible() {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.agent(plistName: "com.fleetconsole.fleetd.plist")
        switch service.status {
        case .enabled:
            FleetLog.info("fleetd agent already registered with launchd")
        case .requiresApproval:
            FleetLog.warn("fleetd agent needs approval in System Settings → General → Login Items")
        default:
            do {
                try service.register()
                FleetLog.info("registered fleetd agent with launchd")
            } catch {
                FleetLog.warn("SMAppService registration unavailable (\(error.localizedDescription)); use Scripts/install-agent.sh")
            }
        }
    }
}

// Top-level code is not main-actor isolated in Swift 5 mode, but it does run on
// the main thread — which is exactly what assumeIsolated asserts.
MainActor.assumeIsolated {
    // Compiled in only by Scripts/surface-sheet.sh, which passes
    // -DFLEET_SURFACE_RENDERER. Runs the whole UI against fixtures, writes a PNG
    // per surface, and exits without ever putting an item in the menu bar.
    #if FLEET_SURFACE_RENDERER
    if SurfaceRenderer.runIfRequested() { exit(0) }
    #endif

    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
    objc_setAssociatedObject(application, "fleetconsole.delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    application.run()
}
