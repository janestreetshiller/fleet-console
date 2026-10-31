import AppKit
import SwiftUI
import Testing
import Vision
@testable import FleetConsoleApp

@Suite(.serialized)
struct VisualHierarchyTests {
    @MainActor @Test("Attention leads the page and spans the supporting columns", arguments: [false, true])
    func attentionIsPrimary(dark: Bool) throws {
        let window = host(HomeModule(model: AppModel(), console: ConsoleModel()), width: 1100, dark: dark)
        defer { window.orderOut(nil) }
        let root = try #require(window.contentView)
        let title = try #require(element("workspace.heading", in: root))
        let priority = try #require(element("home.priority", in: root))
        let supporting = try #require(element("home.agents", in: root))
        let titleFrame = try frame(title)
        let priorityFrame = try frame(priority)
        let supportingFrame = try frame(supporting)
        #expect(titleFrame.minX == priorityFrame.minX)
        #expect(titleFrame.minY >= priorityFrame.maxY)
        #expect(priorityFrame.width > supportingFrame.width * 1.5)
        #expect(priorityFrame.minY >= supportingFrame.maxY)
    }

    @MainActor @Test("Overview distinguishes page identity from primary values and supporting readings", arguments: [false, true])
    func overviewReadingOrder(dark: Bool) throws {
        let window = host(OverviewModule(model: AppModel(), console: ConsoleModel()), width: 980, dark: dark)
        defer { window.orderOut(nil) }
        let root = try #require(window.contentView)
        let heading = try #require(element("workspace.heading", in: root))
        let cpuTitle = try #require(element("telemetry.CPU.title", in: root))
        let cpuValue = try #require(element("telemetry.CPU.value", in: root))
        let glance = try #require(element("overview.glance", in: root))
        #expect(try frame(heading).minY > frame(cpuTitle).maxY)
        #expect(try frame(cpuValue).height > frame(cpuTitle).height)
        #expect(try frame(cpuValue).minY > frame(glance).maxY)
    }

    @MainActor @Test("Sidebar separates monitoring from background work")
    func sidebarGroups() throws {
        let window = host(NavigationSplitView {
            FleetSidebarView(model: AppModel(), console: ConsoleModel())
                .navigationSplitViewColumnWidth(240)
        } detail: { Text("Content") }, width: 980, dark: false)
        defer { window.orderOut(nil) }
        let root = try #require(window.contentView)
        let bitmap = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: #require(bitmap.cgImage)).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        #expect(text.localizedCaseInsensitiveContains("Monitor"))
        #expect(text.localizedCaseInsensitiveContains("Background work"))
    }

    @MainActor private func host<Content: View>(_ content: Content, width: CGFloat, dark: Bool) -> NSWindow {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        if !NSApp.isRunning { NSApp.finishLaunching() }
        _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"),
                          with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: width, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: content)
        window.orderFront(nil)
        for _ in 0..<12 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.025)) }
        return window
    }

    @MainActor private func element(_ id: String, in root: Any) -> NSObject? {
        guard let object = root as? NSObject else { return nil }
        if value("accessibilityIdentifier", from: object) as? String == id
            || value("accessibilityLabel", from: object) as? String == id { return object }
        for child in value("accessibilityChildren", from: object) as? [Any] ?? [] {
            if let found = element(id, in: child) { return found }
        }
        return nil
    }

    @MainActor private func value(_ key: String, from object: NSObject) -> Any? {
        let selector = NSSelectorFromString(key)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    @MainActor private func frame(_ object: NSObject) throws -> NSRect {
        try #require(object.responds(to: NSSelectorFromString("accessibilityFrame")))
        return try #require(object.value(forKey: "accessibilityFrame") as? NSValue).rectValue
    }
}
