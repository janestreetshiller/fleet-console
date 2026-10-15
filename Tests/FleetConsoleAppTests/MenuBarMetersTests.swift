import AppKit
import SwiftUI
import Testing
@testable import FleetConsoleApp

struct MenuBarMetersTests {
    @MainActor @Test("The menu-bar item keeps one width whatever the readings are")
    func metersHoldTheirWidth() {
        func width(_ values: [String]) -> CGFloat {
            MenuBarMeters.image(zip(["CPU", "RAM", "DISK"], values).map {
                MenuBarMeter(label: $0, value: $1)
            }).size.width
        }
        let idle = width(["1%", "9%", "—"])
        #expect(idle == width(["100%", "100%", "100%"]))
        #expect(idle == width(["—", "—", "—"]))
        #expect(MenuBarMeters.image([]).size.height == MenuBarMeters.height)
    }

    @MainActor @Test("The model reports CPU, RAM and disk in that order, unsampled as a dash")
    func modelMeterOrder() {
        let model = AppModel()
        let meters = model.fleetMeters
        #expect(meters.map(\.label) == ["CPU", "RAM", "DISK"])
        #expect(meters.allSatisfy { !$0.value.isEmpty })
    }

    @MainActor @Test("The popover's way to the dashboard is in its header, not a footer")
    func popoverHeaderCarriesTheDashboardAction() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        if !NSApp.isRunning { NSApp.finishLaunching() }
        // SwiftUI builds its accessibility tree only for a client that asks;
        // the other UI suites switch it on the same way.
        _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"),
                          with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        let model = AppModel()
        let host = NSHostingView(rootView: FleetPopover(model: model, openDashboard: {}))
        // In a window, ordered in off-screen: the accessibility tree of a
        // hosting view that has never been in one is not reliably populated.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: FleetMetrics.popoverWidth, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<12 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.025)) }
        func labels(_ object: Any) -> [String] {
            guard let node = object as? NSObject else { return [] }
            let own = (node.responds(to: NSSelectorFromString("accessibilityLabel"))
                ? node.value(forKey: "accessibilityLabel") as? String : nil).map { [$0] } ?? []
            let children = (node.responds(to: NSSelectorFromString("accessibilityChildren"))
                ? node.value(forKey: "accessibilityChildren") as? [Any] : nil) ?? []
            return own + children.flatMap(labels)
        }
        #expect(labels(host).contains { $0.contains("Dashboard") })
        for title in ["CPU", "Memory", "Disk", "Network"] {
            #expect(labels(host).contains("Investigate \(title) with agent"))
        }
    }
}
