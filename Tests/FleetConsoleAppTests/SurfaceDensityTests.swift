import AppKit
import SwiftUI
import Testing
@testable import FleetConsoleApp

@Suite(.serialized)
struct SurfaceDensityTests {
    @MainActor @Test("Page headers are one quiet row, not a second toolbar")
    func quietPageHeader() {
        let view = NSHostingView(rootView: ModuleHeader(title: "Storage", subtitle: "Macintosh HD", symbol: "internaldrive") {
            Button("Scan Now") {}
        }.frame(width: 700))
        let size = view.fittingSize
        print("Module header intrinsic height: \(size.height)")
        #expect(size.height <= 26)
        #expect(size.width == 700)
    }

    @MainActor @Test("The process glance is a bounded ranking rather than a scrolling table")
    func processGlanceFits() async throws {
        let model = AppModel()
        let view = NSHostingView(rootView: ProcessesContent(model: model, openDashboard: {}))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 480, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        let until = Date().addingTimeInterval(5)
        while Date() < until && model.processes.rows.count < 5 {
            try await Task.sleep(for: .milliseconds(50))
            view.layoutSubtreeIfNeeded()
        }
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        #expect(model.processes.rows.count >= 5)
        print("Populated process glance height: \(view.fittingSize.height)")
        func scrolls(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrolls($0) }
        }
        #expect(scrolls(view).isEmpty)
        #expect(view.fittingSize.height <= FleetMetrics.popoverBodyHeight)
    }

    @MainActor @Test("Quick View spends only its natural instrument height")
    func quickViewDoesNotPadToAListViewport() {
        let model = AppModel()
        let view = NSHostingView(rootView: FleetPopover(model: model, openDashboard: {}))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 480, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        let until = Date().addingTimeInterval(0.3)
        while Date() < until { view.layoutSubtreeIfNeeded(); RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
        print("Quick View natural height: \(view.fittingSize.height)")
        #expect(view.fittingSize.height <= 280)
        #expect(view.fittingSize.width == FleetMetrics.popoverWidth)
    }
}
