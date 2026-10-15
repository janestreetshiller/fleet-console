import AppKit
import SwiftUI

// The application's main menu.
//
// The app is AppKit-bootstrapped (status items predate the console window, and
// `MenuBarExtra` cannot render the custom summary glyphs those items use), so
// there is no SwiftUI scene to hang `CommandGroup` on. This is the same
// contract expressed in AppKit: named commands, standard key equivalents,
// routed through `ConsoleCommand` notifications the console window observes.
//
// Menu commands are no-ops when the console is closed — the notifications
// simply have no observer — which is exactly how a menu-bar utility should
// behave.

/// `@MainActor` on the enum rather than each member: every function here touches
/// `NSApp`, `NSMenu` or `NSMenuItem`. The isolation was always required.
@MainActor
enum MainMenu {

    static func install(openConsole: @escaping @MainActor () -> Void) {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        installApplicationMenu(into: mainMenu)
        installEditMenu(into: mainMenu)
        installViewMenu(into: mainMenu, openConsole: openConsole)
        installWindowMenu(into: mainMenu)
    }

    // MARK: Application

    private static func installApplicationMenu(into menu: NSMenu) {
        let item = menu.addItem(withTitle: "FleetConsole", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "FleetConsole")

        submenu.addItem(withTitle: "About FleetConsole",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Hide FleetConsole",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = submenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Quit FleetConsole",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.submenu = submenu
    }

    // MARK: Edit
    //
    // Standard responder-chain items. Without an Edit menu, ⌘C/⌘V/⌘A stop
    // working inside text fields — including the toolbar search field — which
    // is the kind of bug that makes an app feel not-native before you can say
    // why.

    private static func installEditMenu(into menu: NSMenu) {
        let item = menu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Edit")

        submenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        submenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        submenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        submenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        submenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)),
                        keyEquivalent: "a")

        item.submenu = submenu
    }

    // MARK: View

    private static func installViewMenu(into menu: NSMenu, openConsole: @escaping @MainActor () -> Void) {
        let actions = MenuActionTarget.shared
        actions.openConsole = openConsole

        let item = menu.addItem(withTitle: "View", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "View")

        // "Open Dashboard", not "Show Console". One command had three labels —
        // this menu said Show Console, the status-item dropdown said Open
        // Dashboard…, and the popover footer's button said Open Dashboard —
        // which reads as three destinations to anyone who has not opened all
        // three. README documents it as Open Dashboard (⌘0), so that is the name.
        let console = submenu.addItem(withTitle: "Open Dashboard",
                                      action: #selector(MenuActionTarget.showConsole),
                                      keyEquivalent: "0")
        console.keyEquivalentModifierMask = [.command]
        console.target = actions

        submenu.addItem(.separator())

        // Home is the landing surface, so it sits above the modules — but it is
        // not one of them, which is why it takes a shifted equivalent and leaves
        // ⌘1…⌘n bound to exactly the module indices, whatever their count.
        let home = submenu.addItem(withTitle: "Overview",
                                   action: #selector(MenuActionTarget.showHome),
                                   keyEquivalent: "h")
        home.keyEquivalentModifierMask = [.command, .shift]
        home.target = actions

        for entry in moduleItems() { submenu.addItem(entry) }

        submenu.addItem(.separator())

        // The chrome tools. `ConsoleTool.shortcut` is the declared key and this
        // is the only place it is bound, so the rail's tooltips and the menu
        // cannot drift apart.
        for tool in ConsoleTool.allCases {
            let entry = submenu.addItem(withTitle: tool.title,
                                        action: #selector(MenuActionTarget.toggleTool(_:)),
                                        keyEquivalent: String(tool.shortcut.character))
            entry.keyEquivalentModifierMask = [.command, .shift]
            entry.target = actions
            entry.representedObject = tool.rawValue
        }

        submenu.addItem(.separator())

        let search = submenu.addItem(withTitle: "Focus Search",
                                     action: #selector(MenuActionTarget.focusSearch),
                                     keyEquivalent: "k")
        search.target = actions

        let refresh = submenu.addItem(withTitle: "Refresh",
                                      action: #selector(MenuActionTarget.refresh),
                                      keyEquivalent: "r")
        refresh.target = actions

        submenu.addItem(.separator())

        let sidebar = submenu.addItem(withTitle: "Toggle Sidebar",
                                      action: #selector(MenuActionTarget.toggleSidebar),
                                      keyEquivalent: "s")
        sidebar.keyEquivalentModifierMask = [.command, .control]
        sidebar.target = actions

        // The inspector's menu entry. The sidebar's toggle comes free from
        // AppKit; the trailing column's does not, so both halves of the window
        // are reachable from the keyboard by the same route.
        let inspector = submenu.addItem(withTitle: "Toggle Inspector",
                                        action: #selector(MenuActionTarget.toggleInspector),
                                        keyEquivalent: "i")
        inspector.keyEquivalentModifierMask = [.command, .option]
        inspector.target = actions

        submenu.addItem(.separator())

        // There was no Full Screen item here for as long as the window set
        // `.fullScreenNone`, and that was correct: AppKit would never have
        // validated `toggleFullScreen:`, so the entry could only ever render
        // grey, which is rule 10 exactly. The window resizes freely on both
        // axes now and takes `.fullScreenPrimary`, so the capability is real
        // and the chrome comes back with it. `toggleFullScreen:` is AppKit's
        // own responder-chain action — nil target, no shim.
        let fullScreen = submenu.addItem(withTitle: "Enter Full Screen",
                                         action: #selector(NSWindow.toggleFullScreen(_:)),
                                         keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]

        item.submenu = submenu
    }

    // MARK: Shared items

    /// The console modules as menu items, generated from `ConsoleModule.allCases`
    /// and targeted at the shared action object.
    ///
    /// Built once and used twice — the View menu and the status item's dropdown.
    /// The dropdown previously offered no route to a module at all: reaching the
    /// process table from the menu bar meant opening the dashboard and then
    /// finding it, on the app's most-used surface. Duplicating the loop over
    /// there would have meant two lists that drift the moment a module is added,
    /// which is the failure `shortcutIndex` and `allCases` exist to prevent, so
    /// there is one builder instead.
    ///
    /// The equivalents shown are the real ones. They are live whenever the app is
    /// active — the deployment is `.accessory`, so that means the console window
    /// is focused, which is the only context in which selecting a module means
    /// anything anyway.
    static func moduleItems() -> [NSMenuItem] {
        ConsoleModule.allCases.map { module in
            let entry = NSMenuItem(title: module.title,
                                   action: #selector(MenuActionTarget.selectModule(_:)),
                                   keyEquivalent: "\(module.shortcutIndex)")
            entry.keyEquivalentModifierMask = [.command]
            entry.target = MenuActionTarget.shared
            entry.representedObject = module.rawValue
            return entry
        }
    }

    // MARK: Window

    private static func installWindowMenu(into menu: NSMenu) {
        let item = menu.addItem(withTitle: "Window", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Window")

        submenu.addItem(withTitle: "Minimize",
                        action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        submenu.addItem(withTitle: "Zoom",
                        action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        submenu.addItem(withTitle: "Close",
                        action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        item.submenu = submenu
        NSApp.windowsMenu = submenu
    }
}

/// Obj-C reachable target for menu items. Menus outlive any one window, so the
/// target is a shared instance rather than a view controller.
///
/// `@MainActor` states what AppKit guarantees: menu actions dispatch on the main
/// thread, and `openConsole` is installed from `applicationDidFinishLaunching`.
@MainActor
@objc private final class MenuActionTarget: NSObject {
    static let shared = MenuActionTarget()

    var openConsole: (@MainActor () -> Void)?

    @objc func showConsole() {
        openConsole?()
    }

    @objc func focusSearch() {
        openConsole?()
        NotificationCenter.default.post(name: ConsoleCommand.focusSearch, object: nil)
    }

    @objc func refresh() {
        NotificationCenter.default.post(name: ConsoleCommand.refresh, object: nil)
    }

    @objc func selectModule(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String else { return }
        openConsole?()
        NotificationCenter.default.post(name: ConsoleCommand.selectModule, object: nil,
                                        userInfo: [ConsoleCommand.userInfoModule: rawValue])
    }

    @objc func showHome() {
        openConsole?()
        NotificationCenter.default.post(name: ConsoleCommand.showHome, object: nil)
    }

    @objc func toggleTool(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String else { return }
        openConsole?()
        NotificationCenter.default.post(name: ConsoleCommand.toggleTool, object: nil,
                                        userInfo: [ConsoleCommand.userInfoTool: rawValue])
    }

    @objc func toggleSidebar() {
        openConsole?()
        NotificationCenter.default.post(name: ConsoleCommand.toggleSidebar, object: nil)
    }

    @objc func toggleInspector() {
        openConsole?()
        NotificationCenter.default.post(name: ConsoleCommand.toggleInspector, object: nil)
    }
}
