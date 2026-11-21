import AppKit
import SwiftUI

@MainActor
enum MainMenu {

    static func install(openConsole: @escaping @MainActor () -> Void) {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        installApplicationMenu(into: mainMenu)
        installEditMenu(into: mainMenu)
        installViewMenu(into: mainMenu, openConsole: openConsole)
        installWindowMenu(into: mainMenu)
        installHelpMenu(into: mainMenu)
    }

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

    private static func installViewMenu(into menu: NSMenu, openConsole: @escaping @MainActor () -> Void) {
        let actions = MenuActionTarget.shared
        actions.openConsole = openConsole

        let item = menu.addItem(withTitle: "View", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "View")

        let console = submenu.addItem(withTitle: "Open Dashboard",
                                      action: #selector(MenuActionTarget.showConsole),
                                      keyEquivalent: "0")
        console.keyEquivalentModifierMask = [.command]
        console.target = actions

        submenu.addItem(.separator())

        submenu.addItem(needsAttentionItem())

        for entry in moduleItems() { submenu.addItem(entry) }

        submenu.addItem(.separator())

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

        let inspector = submenu.addItem(withTitle: "Toggle Inspector",
                                        action: #selector(MenuActionTarget.toggleInspector),
                                        keyEquivalent: "i")
        inspector.keyEquivalentModifierMask = [.command, .option]
        inspector.target = actions

        submenu.addItem(.separator())

        let fullScreen = submenu.addItem(withTitle: "Enter Full Screen",
                                         action: #selector(NSWindow.toggleFullScreen(_:)),
                                         keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]

        item.submenu = submenu
    }

    static func needsAttentionItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Needs Attention",
                              action: #selector(MenuActionTarget.showHome), keyEquivalent: "h")
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = MenuActionTarget.shared
        return item
    }

    static func helpItems() -> [NSMenuItem] {
        let guide = NSMenuItem(title: "FleetConsole Guide",
                               action: #selector(MenuActionTarget.showGuide), keyEquivalent: "")
        guide.target = MenuActionTarget.shared
        let setup = NSMenuItem(title: "fleetctl Setup…",
                               action: #selector(MenuActionTarget.showFleetctlSetup), keyEquivalent: "")
        setup.target = MenuActionTarget.shared
        return [guide, setup]
    }

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

    private static func installHelpMenu(into menu: NSMenu) {
        let item = menu.addItem(withTitle: "Help", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Help")
        for entry in helpItems() { submenu.addItem(entry) }
        item.submenu = submenu
        NSApp.helpMenu = submenu
    }
}

@MainActor
enum FleetctlHelp {
    static let guideURL = URL(string: "https://github.com/janestreetshiller/fleet-console#readme")!
    static let referenceURL = URL(string: "https://github.com/janestreetshiller/fleet-console/blob/main/docs/CLI.md")!

    static func executable(resourceURL: URL?) -> URL? {
        guard let candidate = resourceURL?.appendingPathComponent("bin/fleetctl") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: candidate.path) else { return nil }
        return candidate
    }

    static func doctorCommand(executable: URL) -> String {
        "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "' doctor"
    }

    static func showSetup() {
        let alert = NSAlert()
        let executable = executable(resourceURL: Bundle.main.resourceURL)
        alert.messageText = "Use fleetctl from Terminal"
        if let executable {
            alert.informativeText = "fleetctl is included with this copy of FleetConsole. It records who started background work, why it is running, and when its lease expires.\n\nPaste this command into Terminal to check the controller:\n\n"
                + doctorCommand(executable: executable)
                + "\n\nUse this full path until fleetctl is on your PATH."
            alert.addButton(withTitle: "Copy Doctor Command")
        } else {
            alert.informativeText = "This copy does not contain an executable fleetctl at Resources/bin/fleetctl. Packaged FleetConsole apps include it; when running from source, build the fleetctl product with Swift. The CLI reference explains commands and controller setup."
        }
        alert.addButton(withTitle: "CLI Reference")
        alert.addButton(withTitle: "Close")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if let executable, response == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(doctorCommand(executable: executable), forType: .string)
        } else if response == (executable == nil ? .alertFirstButtonReturn : .alertSecondButtonReturn) {
            NSWorkspace.shared.open(referenceURL)
        }
    }
}

@MainActor
@objc private final class MenuActionTarget: NSObject {
    static let shared = MenuActionTarget()

    var openConsole: (@MainActor () -> Void)?

    @objc func showConsole() {
        openConsole?()
    }

    @objc func showGuide() {
        NSWorkspace.shared.open(FleetctlHelp.guideURL)
    }

    @objc func showFleetctlSetup() {
        FleetctlHelp.showSetup()
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
