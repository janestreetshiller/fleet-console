import AppKit
import Foundation
import Testing
@testable import FleetConsoleApp

@Suite(.serialized)
struct MenuNavigationTests {
    @MainActor @Test("Needs Attention opens the dashboard before routing to local attention")
    func attentionFromClosedDashboard() throws {
        _ = NSApplication.shared
        let oldMenu = NSApp.mainMenu
        let oldHelp = NSApp.helpMenu
        var controller: ConsoleWindowController?
        var openCount = 0
        MainMenu.install {
            openCount += 1
            controller = ConsoleWindowController(model: AppModel())
            controller?.console.selectedDeviceID = "remote-before-command"
        }
        defer {
            MainMenu.install {}
            NSApp.mainMenu = oldMenu
            NSApp.helpMenu = oldHelp
        }
        let item = MainMenu.needsAttentionItem()
        #expect(item.title == "Needs Attention")
        #expect(item.keyEquivalent == "h")
        #expect(item.keyEquivalentModifierMask == [.command, .shift])
        let action = try #require(item.action)
        #expect(NSApp.sendAction(action, to: item.target, from: item))
        let opened = try #require(controller)
        #expect(openCount == 1)
        #expect(opened.window == nil)
        #expect(opened.console.atHome)
        #expect(opened.console.isLocalDeviceSelected)
    }

    @MainActor @Test("View and status navigation use the same attention label and real shortcut")
    func sharedAttentionLabel() throws {
        _ = NSApplication.shared
        let oldMenu = NSApp.mainMenu
        let oldHelp = NSApp.helpMenu
        MainMenu.install {}
        defer {
            NSApp.mainMenu = oldMenu
            NSApp.helpMenu = oldHelp
        }
        let view = try #require(NSApp.mainMenu?.item(withTitle: "View")?.submenu)
        let item = try #require(view.item(withTitle: "Needs Attention"))
        #expect(view.item(withTitle: "Home") == nil)
        #expect(item.action == MainMenu.needsAttentionItem().action)
        #expect(item.keyEquivalentModifierMask == [.command, .shift])
        #expect(view.item(withTitle: "Open Dashboard")?.keyEquivalent == "0")
    }

    @MainActor @Test("The native Help menu exposes the guide and fleetctl setup")
    func nativeHelpMenu() throws {
        _ = NSApplication.shared
        let oldMenu = NSApp.mainMenu
        let oldHelp = NSApp.helpMenu
        MainMenu.install {}
        defer {
            NSApp.mainMenu = oldMenu
            NSApp.helpMenu = oldHelp
        }
        let help = try #require(NSApp.mainMenu?.item(withTitle: "Help")?.submenu)
        #expect(NSApp.helpMenu === help)
        #expect(help.items.map(\.title) == ["FleetConsole Guide", "fleetctl Setup…"])
        #expect(help.items.allSatisfy { $0.action != nil && $0.target != nil })
    }

    @MainActor @Test("fleetctl setup only offers an executable file in this bundle")
    func setupRequiresExecutable() throws {
        let resources = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: resources) }
        let executable = resources.appendingPathComponent("bin/fleetctl")
        #expect(FleetctlHelp.executable(resourceURL: nil) == nil)
        #expect(FleetctlHelp.executable(resourceURL: resources) == nil)
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: executable.path)
        #expect(FleetctlHelp.executable(resourceURL: resources) == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        #expect(FleetctlHelp.executable(resourceURL: resources) == executable)
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.createDirectory(at: executable, withIntermediateDirectories: false)
        #expect(FleetctlHelp.executable(resourceURL: resources) == nil)
    }

    @MainActor @Test("The copied doctor command executes the exact CLI path through shell metacharacters")
    func doctorCommandPreservesPath() throws {
        let resources = FileManager.default.temporaryDirectory
            .appendingPathComponent("Fleet Console's $(false) `false` " + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: resources) }
        let executable = resources.appendingPathComponent("bin/fleetctl")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nprintf '%s' \"$1\"\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", FleetctlHelp.doctorCommand(executable: executable)]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: data, as: UTF8.self) == "doctor")
    }
}
