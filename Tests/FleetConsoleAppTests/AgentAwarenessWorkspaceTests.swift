import AppKit
import SwiftUI
import Testing
import FleetCore
@testable import FleetConsoleApp

@Suite(.serialized)
struct AgentAwarenessWorkspaceTests {
    @MainActor @Test("The default workspace is an activity map, never a process table", arguments: [false, true])
    func viewport(dark: Bool) throws {
        for size in [NSSize(width: 640, height: 676), NSSize(width: 982, height: 720), NSSize(width: 1560, height: 900)] {
            let (model, console) = fixture()
            let window = host(OverviewWorkspace(model: model, console: console), size: size, dark: dark)
            defer { window.orderOut(nil) }
            let root = try #require(window.contentView)
            let canvas = try #require(element("awareness.canvas", in: root))
            #expect(try frame(canvas).width >= size.width * 0.95)
            #expect(try frame(canvas).height >= size.height * 0.90)
            #expect(element("awareness.summary", in: root) != nil)
            #expect(element("awareness.zoom.in", in: root) != nil)
            #expect(element("awareness.fit", in: root) != nil)
            #expect(element("console.processes", in: root) == nil)
            #expect(element("overview.process-map", in: root) == nil)
            #expect(nodes(root).contains { (value("accessibilityIdentifier", from: $0) as? String ?? "").contains("fixture-session") })
            try capture(window, name: "awareness-\(Int(size.width))-\(dark ? "dark" : "light")")
        }
    }

    @MainActor @Test("Selecting an agent exposes its actual activity and navigable relationships")
    func selectActivity() throws {
        let (model, console) = fixture()
        let window = host(OverviewWorkspace(model: model, console: console), size: NSSize(width: 1560, height: 900), dark: true)
        defer { window.orderOut(nil) }
        let root = try #require(window.contentView)
        let node = try #require(nodes(root).first {
            (value("accessibilityIdentifier", from: $0) as? String ?? "").contains("awareness.node.") &&
            (value("accessibilityIdentifier", from: $0) as? String ?? "").contains("fixture-session")
        })
        #expect(press(node))
        settle()
        let detail = try #require(element("awareness.detail", in: root))
        #expect(labels(detail).contains { $0.contains("TEST DATA: editing the parser") })
        #expect(element("awareness.focus", in: root) != nil)
        let before = labels(try #require(element("awareness.zoom.value", in: root))).joined()
        #expect(press(try #require(element("awareness.zoom.in", in: root))))
        settle()
        let after = labels(try #require(element("awareness.zoom.value", in: root))).joined()
        #expect(before != after)
        #expect(press(try #require(element("awareness.close", in: root))))
        settle()
        #expect(element("awareness.detail", in: root) == nil)
        #expect(console.module == .overview)
    }

    @MainActor @Test("Registry membership updates preserve a focused agent's native frame")
    func focusedAgentStaysStillWhenGraphBoundsChange() throws {
        let (model, console) = fixture()
        let window = host(OverviewWorkspace(model: model, console: console), size: NSSize(width: 1560, height: 900), dark: true)
        defer { window.orderOut(nil) }
        let root = try #require(window.contentView)
        let agentID = "session:fixture-session"
        let projectID = "project:/TEST-DATA/project"
        let accessibilityID = "awareness.node." + agentID
        #expect(press(try #require(element(accessibilityID, in: root))))
        settle()
        #expect(press(try #require(element("awareness.focus", in: root))))
        for _ in 0..<3 { settle() } // Allow the production focus animation to finish.
        let beforeFrame = try frame(#require(element(accessibilityID, in: root)))
        let before = AwarenessGraph.build(sessions: model.sessions, processes: model.processes.rows,
            processCapturedAt: model.processes.capturedAt, topology: model.topology)
        let sessions = model.sessions
        let additionalServices = (0..<12).map { index in
            ServiceRecord(id: "additional-service-\(index)", friendlyName: "TEST DATA additional service \(index)",
                ownerAgent: "additional-owner-\(index)", purpose: "TEST DATA camera regression", command: ["fixture"],
                cwd: "/TEST-DATA/other-project", leaseExpiresAt: Date().addingTimeInterval(300),
                leaseTTLSec: 300, state: .running)
        }
        model.apply(Snapshot(daemon: DaemonInfo(version: "TEST DATA", pid: 0, startedAt: Date()),
            services: model.serviceRows.map(\.record) + additionalServices, sessions: sessions))
        for _ in 0..<3 { settle() }
        let after = AwarenessGraph.build(sessions: model.sessions, processes: model.processes.rows,
            processCapturedAt: model.processes.capturedAt, topology: model.topology)
        #expect(before.bounds != after.bounds)
        #expect(CGPoint(x: before.bounds.midX, y: before.bounds.midY) != CGPoint(x: after.bounds.midX, y: after.bounds.midY))
        for id in [agentID, projectID] {
            let previous = try #require(before.nodes.first { $0.id == id })
            let current = try #require(after.nodes.first { $0.id == id })
            #expect(previous.position == current.position)
        }
        let afterFrame = try frame(#require(element(accessibilityID, in: root)))
        #expect(abs(beforeFrame.minX - afterFrame.minX) < 0.5)
        #expect(abs(beforeFrame.minY - afterFrame.minY) < 0.5)
        #expect(abs(beforeFrame.width - afterFrame.width) < 0.5)
        #expect(abs(beforeFrame.height - afterFrame.height) < 0.5)
        #expect(element("awareness.detail", in: root) != nil)
    }

    @MainActor private func fixture() -> (AppModel, ConsoleModel) {
        let model = AppModel(connectToController: false)
        let record = ServiceRecord(id: "fixture-service", friendlyName: "TEST DATA parser worker", ownerAgent: "fixture-owner",
            purpose: "TEST DATA layout only", command: ["fixture"], cwd: "/TEST-DATA/project",
            leaseExpiresAt: Date().addingTimeInterval(300), leaseTTLSec: 300, state: .running)
        var session = AgentSession(id: "fixture-session", tool: "TEST DATA agent", pid: 123,
            project: "/TEST-DATA/project")
        session.preview = "TEST DATA: editing the parser"
        model.apply(Snapshot(daemon: DaemonInfo(version: "TEST DATA", pid: 0, startedAt: Date()), services: [record], sessions: [session]))
        return (model, ConsoleModel())
    }

    @MainActor private func host<Content: View>(_ content: Content, size: NSSize, dark: Bool) -> NSWindow {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        if !NSApp.isRunning { NSApp.finishLaunching() }
        _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"),
                          with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
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
    @MainActor private func nodes(_ root: Any) -> [NSObject] {
        guard let object = root as? NSObject else { return [] }
        return [object] + (value("accessibilityChildren", from: object) as? [Any] ?? []).flatMap { nodes($0) }
    }
    @MainActor private func labels(_ root: Any) -> [String] {
        nodes(root).flatMap { object in [value("accessibilityLabel", from: object) as? String, value("accessibilityValue", from: object) as? String].compactMap { $0 } }
    }
    @MainActor private func element(_ id: String, in root: Any) -> NSObject? {
        nodes(root).first { value("accessibilityIdentifier", from: $0) as? String == id }
    }
    @MainActor private func frame(_ object: NSObject) throws -> NSRect { try #require(value("accessibilityFrame", from: object) as? NSRect) }
    @MainActor private func press(_ object: NSObject) -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector)
    }
    @MainActor private func capture(_ window: NSWindow, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["FLEETCONSOLE_SURFACE_OUTPUT"] else { return }
        let root = try #require(window.contentView)
        let bitmap = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
}
