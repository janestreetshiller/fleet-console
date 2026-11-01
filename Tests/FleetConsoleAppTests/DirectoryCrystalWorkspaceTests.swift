import AppKit
import SwiftUI
import Testing
import FleetCore
@testable import FleetConsoleApp

@Suite(.serialized)
struct DirectoryCrystalWorkspaceTests {
    @MainActor @Test("Real directory roots render behind activity and branches can expand", arguments: [false, true])
    func directorySubstrate(dark: Bool) async throws {
        let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_CRYSTAL_TEST_TMP"] ?? FileManager.default.temporaryDirectory.path).resolvingSymlinksInPath()
        let root = base.appendingPathComponent("TEST-DATA-crystal-" + UUID().uuidString)
        let ui = root.appendingPathComponent("Sources/App/UI")
        let leaf = ui.appendingPathComponent("Components/Views")
        try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Tests"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(connectToController: false)
        var session = AgentSession(id: "crystal-session", tool: "TEST DATA agent", pid: 123, project: root.appendingPathComponent("Sources/App").path)
        session.preview = "TEST DATA: directory integration"
        model.apply(Snapshot(daemon: DaemonInfo(version: "TEST DATA", pid: 0, startedAt: Date()), services: [], sessions: [session]))
        let console = ConsoleModel()
        let window = host(OverviewWorkspace(model: model, console: console, directoryRoots: [root.path]), dark: dark)
        defer { window.orderOut(nil) }
        let content = try #require(window.contentView)
        for _ in 0..<50 {
            if element("directory.node." + ui.path, in: content) != nil { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(element("directory.structure", in: content) != nil)
        let observed = DirectoryCrystal.scan(roots: [root.path], requiredPaths: [session.project!])
        #expect(labels(in: content).contains { $0.contains("\(observed.nodes.count) folders") })
        #expect(element("directory.fit", in: content) != nil)
        let branch = try #require(element("directory.node." + ui.path, in: content))
        #expect(element("directory.node." + ui.appendingPathComponent("Components").path, in: content) == nil)
        #expect(press(branch))
        settle()
        #expect(element("directory.detail", in: content) != nil)
        #expect(press(try #require(element("directory.expand", in: content))))
        for _ in 0..<50 {
            if element("directory.node." + leaf.path, in: content) != nil { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(element("directory.node." + leaf.path, in: content) != nil)
        #expect(element("awareness.node.session:crystal-session", in: content) != nil)
        if let directory = ProcessInfo.processInfo.environment["FLEETCONSOLE_SURFACE_OUTPUT"] {
            let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("directory-crystal-\(dark ? "dark" : "light").png"))
        }
    }

    @MainActor private func host<Content: View>(_ content: Content, dark: Bool) -> NSWindow {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        if !NSApp.isRunning { NSApp.finishLaunching() }
        _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1560, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSApp.appearance
        window.contentView = NSHostingView(rootView: content)
        window.orderBack(nil)
        settle()
        return window
    }
    @MainActor private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }
    @MainActor private func value(_ name: String, from object: NSObject) -> Any? {
        let selector = NSSelectorFromString(name)
        return object.responds(to: selector) ? object.value(forKey: name) : nil
    }
    @MainActor private func labels(in root: Any) -> [String] {
        guard let object = root as? NSObject else { return [] }
        return [value("accessibilityLabel", from: object) as? String, value("accessibilityValue", from: object) as? String].compactMap { $0 }
            + (value("accessibilityChildren", from: object) as? [Any] ?? []).flatMap { labels(in: $0) }
    }
    @MainActor private func element(_ id: String, in root: Any) -> NSObject? {
        guard let object = root as? NSObject else { return nil }
        if value("accessibilityIdentifier", from: object) as? String == id { return object }
        for child in value("accessibilityChildren", from: object) as? [Any] ?? [] {
            if let found = element(id, in: child) { return found }
        }
        return nil
    }
    @MainActor private func press(_ object: NSObject) -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector)
    }
}
