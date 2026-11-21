import AppKit
import SwiftUI
import ServiceManagement
import FleetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let openDashboardNotification = Notification.Name("com.fleetconsole.openDashboard")

    private let model: AppModel = {
        #if FLEET_SURFACE_RENDERER
        let arguments = CommandLine.arguments
        let argumentPath = arguments.firstIndex(of: "--billing-browser-capture").flatMap {
            $0 + 1 < arguments.count ? arguments[$0 + 1] : nil
        }
        if let path = argumentPath ?? Bundle.main.object(forInfoDictionaryKey: "FleetConsoleVerificationBrowserCapture") as? String {
            let destination = URL(fileURLWithPath: path)
            let billing = OurosBilling(useKeychain: false, openBrowser: { url in
                do {
                    try Data(url.absoluteString.utf8).write(to: destination, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                } catch { FleetLog.warn("Could not record the verification browser destination") }
            })
            return AppModel(billing: billing)
        }
        #endif
        return AppModel()
    }()
    private var fleetItem: MenuBarItemController!
    private var consoleWindow: ConsoleWindowController?
    private var welcomeWindow: WelcomeWindowController?
    private var taskComposer: TaskComposerWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOffToRunningInstance() { return }
        let review = CommandLine.arguments.contains("--review")
            || Bundle.main.object(forInfoDictionaryKey: "FleetConsoleReviewBuild") as? Bool == true

        MainMenu.install { [weak self] in self?.showDashboard() }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showDashboard),
            name: Self.openDashboardNotification, object: nil)

        if !review { Notifier.requestAuthorizationIfNeeded() }

        fleetItem = MenuBarItemController(
            identifier: "fleet",
            contentView: FleetPopover(model: model,
                                      openDashboard: { [weak self] in self?.showDashboard() }),
            summary: { [model] in
                MenuBarItemController.Summary(
                    meters: model.fleetMeters,
                    alert: model.fleetAlert,
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

        if !review { registerHelperIfPossible() }
        observeModel()
        if !review { showWelcomeIfDue() }

        if review || CommandLine.arguments.contains("--dashboard")
            || ProcessInfo.processInfo.environment["FLEETCONSOLE_DASHBOARD"] == "1" {
            showDashboard()
        }
    }

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

    private func observeModel() {
        withObservationTracking {
            _ = model.fleetMeters
            _ = model.fleetAlert
            _ = model.fleetTint
            _ = model.fleetTooltip
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.fleetItem?.refresh()
                self?.observeModel()
            }
        }
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()

        let quickView = NSMenuItem(title: FleetSection.quickView.menuTitle,
                                   action: #selector(showQuickView), keyEquivalent: "")
        quickView.target = self
        quickView.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: nil)
        menu.addItem(quickView)

        let attention = MainMenu.needsAttentionItem()
        attention.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)
        menu.addItem(attention)

        if FleetSection.agents.isEnabled(model.settings) {
            let title = model.awaitingReplyCount > 0
                ? "Agents — \(model.awaitingReplyCount) awaiting your answer" : "Agents"
            let agents = NSMenuItem(title: title, action: #selector(showAgents), keyEquivalent: "")
            agents.target = self
            agents.image = NSImage(systemSymbolName: "person.2", accessibilityDescription: nil)
            menu.addItem(agents)
        }

        let dashboard = NSMenuItem(title: "Open Dashboard",
                                   action: #selector(showDashboard), keyEquivalent: "0")
        dashboard.keyEquivalentModifierMask = [.command]
        dashboard.target = self
        menu.addItem(dashboard)

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Monitor This Mac"))
        let modules = MainMenu.moduleItems()
        for (module, item) in zip(ConsoleModule.allCases, modules)
            where [.overview, .processes, .storage].contains(module) {
            item.image = NSImage(systemSymbolName: module.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        let network = NSMenuItem(title: FleetSection.connections.menuTitle,
                                action: #selector(showNetwork), keyEquivalent: "")
        network.image = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
        network.target = self
        menu.addItem(network)

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Background Work"))
        for (module, item) in zip(ConsoleModule.allCases, modules)
            where [.services, .events, .plists].contains(module) {
            item.image = NSImage(systemSymbolName: module.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        let newTask = NSMenuItem(title: "New Task…", action: #selector(showNewTask), keyEquivalent: "n")
        newTask.keyEquivalentModifierMask = [.command]
        newTask.target = self
        menu.addItem(newTask)
        let reconcile = NSMenuItem(title: "Find Background Processes",
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
        let welcome = NSMenuItem(title: "Replay Welcome",
                                 action: #selector(replayWelcome), keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Help"))
        for item in MainMenu.helpItems() { menu.addItem(item) }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit FleetConsole",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func showQuickView() {
        model.requestedSection = .quickView
        fleetItem?.showPopover()
    }

    @objc private func showNetwork() {
        model.requestedSection = .connections
        fleetItem?.showPopover()
    }

    @objc private func showAgents() {
        model.requestedSection = .agents
        fleetItem?.showPopover()
    }

    @objc private func showNewTask() {
        let composer = TaskComposerWindowController(agentProfiles: model.agentProfiles)
        taskComposer = composer
        composer.show()
    }

    @objc private func reconcile() { model.reconcileNow() }
    @objc private func openConfig() { model.openConfigFile() }
    @objc private func revealLogs() { model.revealInFinder(FleetPaths.logs.path) }

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

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--design-core-identity") {
        let identity = [
            "version": OurosCoreTokens.version,
            "sourceSHA256": OurosCoreTokens.sourceSHA256,
            "brandSignal": String(format: "#%06X", OurosCoreTokens.brandSignalHex),
            "actionBackground": String(format: "#%06X", OurosCoreTokens.actionBackgroundHex),
            "actionForeground": String(format: "#%06X", OurosCoreTokens.actionForegroundHex)
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            exit(0)
        } catch {
            fputs("Cannot encode design core identity.\n", stderr)
            exit(1)
        }
    }
    #if FLEET_SURFACE_RENDERER
    if CommandLine.arguments.contains(SurfaceRenderer.overviewOnlyFlag),
       SurfaceRenderer.runIfRequested() { exit(0) }
    if LiveVerification.runIfRequested() { exit(0) }
    if SurfaceRenderer.runIfRequested() { exit(0) }
    #endif

    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    #if FLEET_SURFACE_RENDERER
    let reviewWindow = Bundle.main.object(forInfoDictionaryKey: "FleetConsoleReviewBuild") as? Bool == true
    application.setActivationPolicy(reviewWindow ? .regular : .accessory)
    #else
    application.setActivationPolicy(.accessory)
    #endif
    objc_setAssociatedObject(application, "fleetconsole.delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    application.run()
}
