import AppKit
import SwiftUI
import Testing
import FleetCore
@testable import FleetConsoleApp

@Suite(.serialized)
struct ConsolidatedConsoleTests {
    @MainActor @Test("The console spends its viewport on processes, not stacked instrument cards", arguments: [false, true])
    func viewport(dark: Bool) throws {
        for size in [NSSize(width: 640, height: 676), NSSize(width: 982, height: 676), NSSize(width: 1560, height: 856)] {
            let model = AppModel()
            let window = host(OverviewWorkspace(model: model, console: ConsoleModel()), size: size, dark: dark)
            defer { window.orderOut(nil) }
            let root = try #require(window.contentView)
            let resources = try #require(element("console.resources", in: root))
            let processes = try #require(element("console.processes", in: root))
            #expect(try frame(resources).height <= 180)
            #expect(try frame(processes).height >= size.height * 0.55)
            #expect(element("overview.process-map", in: root) == nil)
            #expect(element("overview.processes", in: root) == nil)
            #expect(element("overview.focus", in: root) == nil)
            try capture(window, name: "console-\(Int(size.width))-\(dark ? "dark" : "light")")
        }
    }

    @MainActor @Test("Populated managed work and detected sessions remain compact", arguments: [false, true])
    func populatedWork(dark: Bool) throws {
        let model = AppModel(connectToController: false)
        let service = ServiceRecord(id: "fixture-service", friendlyName: "TEST DATA service", ownerAgent: "fixture-owner",
            purpose: "TEST DATA layout only", command: ["fixture"], cwd: "/TEST-DATA",
            leaseExpiresAt: Date().addingTimeInterval(300), leaseTTLSec: 300, state: .running)
        model.apply(Snapshot(daemon: DaemonInfo(version: "TEST DATA", pid: 0, startedAt: Date()),
            services: [service], sessions: [AgentSession(id: "fixture-session", tool: "TEST DATA agent", pid: 123, project: "/TEST-DATA/project")]))
        let window = host(OverviewWorkspace(model: model, console: ConsoleModel()),
                          size: NSSize(width: 982, height: 676), dark: dark)
        defer { window.orderOut(nil) }
        let root = try #require(window.contentView)
        #expect(element("console.service.fixture-service", in: root) != nil)
        #expect(element("console.session.fixture-session", in: root) != nil)
        let work = try #require(element("console.work", in: root))
        let processes = try #require(element("console.processes", in: root))
        #expect(try frame(work).height <= 120)
        #expect(try frame(processes).height >= 676 * 0.55)
    }

    @MainActor private func host<Content: View>(_ content: Content, size: NSSize, dark: Bool) -> NSWindow {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        if !NSApp.isRunning { NSApp.finishLaunching() }
        _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: content.background(Color(nsColor: .windowBackgroundColor)))
        window.orderFront(nil)
        for _ in 0..<12 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.025)) }
        return window
    }

    @MainActor private func element(_ id: String, in root: Any) -> NSObject? {
        guard let object = root as? NSObject else { return nil }
        if value("accessibilityIdentifier", object) as? String == id { return object }
        for child in value("accessibilityChildren", object) as? [Any] ?? [] {
            if let found = element(id, in: child) { return found }
        }
        return nil
    }

    @MainActor private func value(_ key: String, _ object: NSObject) -> Any? {
        let selector = NSSelectorFromString(key)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    @MainActor private func frame(_ object: NSObject) throws -> NSRect {
        try #require(object.responds(to: NSSelectorFromString("accessibilityFrame")))
        return try #require(object.value(forKey: "accessibilityFrame") as? NSValue).rectValue
    }

    @MainActor private func capture(_ window: NSWindow, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["FLEET_CONSOLE_CAPTURE_DIR"] else { return }
        let root = try #require(window.contentView?.superview)
        let bitmap = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let dir = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent(name + ".png"))
    }
}
