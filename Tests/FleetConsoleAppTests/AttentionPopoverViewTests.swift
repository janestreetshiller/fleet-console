import AppKit
import SwiftUI
import Testing
import FleetCore
@testable import FleetConsoleApp

@Suite(.serialized)
struct AttentionPopoverViewTests {
    @MainActor @Test("Orphaned controller, crash and device alerts explain themselves and open the dashboard")
    func orphanedAlertsAreVisibleAndActionable() throws {
        let model = AppModel()
        DaemonClient.shared.stop() // This test process only; never signal fleetd.
        let items = [
            AttentionItem(id: "controller", severity: .critical, title: "Controller crash-loop", detail: "Review repeated controller exits"),
            AttentionItem(id: "crash", severity: .critical, title: "Indexer crashed", detail: "Review the last service exit", serviceID: "finished-service"),
            AttentionItem(id: "device", severity: .warning, title: "Device unreachable", detail: "Review its connection")
        ]
        var opened = 0
        let window = host(ServicesContent(model: model, openDashboard: { opened += 1 }))
        defer { window.orderOut(nil) }
        apply(items, to: model)
        settle()
        #expect(model.activeServices.isEmpty)
        for item in items {
            let button = try #require(element("attention.\(item.id)", in: window.contentView!))
            #expect(value("accessibilityLabel", from: button) as? String == "\(item.title). \(item.detail)")
            #expect(press(button))
        }
        #expect(opened == 3)
    }

    @MainActor @Test("Attention overflow is an actionable dashboard handoff")
    func overflowOpensDashboard() throws {
        let model = AppModel()
        DaemonClient.shared.stop()
        let items = (0..<8).map {
            AttentionItem(id: "alert-\($0)", severity: .warning, title: "Alert \($0)", detail: "Review details")
        }
        var opened = 0
        let window = host(ServicesContent(model: model, openDashboard: { opened += 1 }))
        defer { window.orderOut(nil) }
        apply(items, to: model)
        settle()
        #expect(element("attention.alert-5", in: window.contentView!) != nil)
        #expect(element("attention.alert-6", in: window.contentView!) == nil)
        let more = try #require(element("attention.dashboard", in: window.contentView!))
        #expect(press(more))
        #expect(opened == 1)
        #expect(window.contentView!.frame.width == FleetMetrics.popoverWidth)
    }

    @MainActor @Test("An active service alert still expands its service instead of opening the dashboard")
    func activeServiceIsRevealedInline() throws {
        let model = AppModel()
        DaemonClient.shared.stop()
        let service = ServiceRecord(id: "active-service", friendlyName: "Demo API", ownerAgent: "demo",
                                    purpose: "serve requests", command: ["python3"], cwd: "/fixture/project",
                                    leaseExpiresAt: Date().addingTimeInterval(3600), leaseTTLSec: 3600)
        let item = AttentionItem(id: "active", severity: .warning, title: "Demo API degraded",
                                 detail: "Review health checks", serviceID: service.id)
        var expanded: String?
        var opened = 0
        let section = AttentionSection(model: model,
                                       expandedService: Binding(get: { expanded }, set: { expanded = $0 }),
                                       openDashboard: { opened += 1 })
        let window = host(section)
        defer { window.orderOut(nil) }
        apply([item], services: [service], to: model)
        settle()
        let button = try #require(element("attention.active", in: window.contentView!))
        #expect(press(button))
        #expect(expanded == service.id)
        #expect(opened == 0)
    }

    @MainActor private func apply(_ items: [AttentionItem], services: [ServiceRecord] = [], to model: AppModel) {
        model.apply(Snapshot(daemon: DaemonInfo(version: "fixture", pid: 0, startedAt: Date()),
                             services: services, attention: items))
        model.connected = true
        model.connectionError = nil
    }

    @MainActor private func host<Content: View>(_ view: Content) -> NSWindow {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.finishLaunching()
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let hosting = NSHostingView(rootView: view.frame(width: FleetMetrics.popoverWidth)
            .accessibilityElement(children: .contain))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: FleetMetrics.popoverWidth, height: 420),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)
        settle()
        return window
    }

    @MainActor private func settle() {
        for _ in 0..<8 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.025)) }
    }

    @MainActor private func element(_ id: String, in root: Any) -> NSObject? {
        guard let object = root as? NSObject else { return nil }
        if value("accessibilityIdentifier", from: object) as? String == id { return object }
        for child in value("accessibilityChildren", from: object) as? [Any] ?? [] {
            if let found = element(id, in: child) { return found }
        }
        return nil
    }

    @MainActor private func value(_ getter: String, from object: NSObject) -> Any? {
        let selector = NSSelectorFromString(getter)
        return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
    }

    @MainActor private func press(_ object: NSObject) -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector)
    }
}
