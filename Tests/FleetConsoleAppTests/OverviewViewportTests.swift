import AppKit
import SwiftUI
import Testing
import Vision
import FleetCore
@testable import FleetConsoleApp

@Suite(.serialized)
struct OverviewViewportTests {
    @MainActor @Test("The compact Overview has no main vertical scroll view")
    func compactOverviewDoesNotScroll() throws {
        let model = AppModel()
        let console = ConsoleModel()
        let window = host(OverviewModule(model: model, console: console), size: NSSize(width: 982, height: 638))
        defer { window.orderOut(nil) }
        let root = try #require(window.contentView)
        let scrolls = scrollViews(in: root)
        for scroll in scrolls {
            let overflow = (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height
            print("Overview main vertical overflow: \(overflow)pt")
        }
        #expect(scrolls.isEmpty)
        try capture(window, name: "overview-module-compact-light")
    }

    @MainActor @Test("Secondary metric details are available without expanding the main viewport")
    func secondaryDetailsAreSeparate() throws {
        let model = AppModel()
        let window = host(OverviewModule(model: model, console: ConsoleModel()), size: NSSize(width: 982, height: 638))
        defer { window.orderOut(nil) }
        let root = try #require(window.contentView)
        #expect(press(try #require(element("overview.metrics.details", in: root))))
        settle()
        let sheet = try #require(window.attachedSheet)
        defer { window.endSheet(sheet) }
        let sheetRoot = try #require(sheet.contentView)
        #expect(!scrollViews(in: sheetRoot).isEmpty)
        #expect(labels(in: sheetRoot).contains { $0.contains("Disk") })
        #expect(labels(in: sheetRoot).contains { $0.contains("GPU") })
        #expect(labels(in: sheetRoot).contains { $0.contains("Network") })
        #expect(labels(in: sheetRoot).contains { $0.contains("Sensors") })
        try capture(sheet, name: "overview-metrics-sheet-light")
        #expect(press(try #require(element("overview.metrics.done", in: sheetRoot))))
        settle()
        #expect(window.attachedSheet == nil)
        #expect(scrollViews(in: root).isEmpty)
    }

    @MainActor @Test("The process preview caps the real rows and routes inspect and View All")
    func processCapAndNavigation() throws {
        let console = ConsoleModel()
        let rows = (1...8).map { process(pid: Int32($0), name: "worker-\($0)", bytes: Int64($0 * 1_000)) }
        let window = host(OverviewProcessPreview(model: AppModel(), rows: rows, query: "", limit: 3, console: console),
                          size: NSSize(width: 940, height: 170))
        defer { window.orderOut(nil) }
        let root = try #require(window.contentView)
        #expect(scrollViews(in: root).isEmpty)
        #expect(element("overview.process.8", in: root) != nil)
        #expect(element("overview.process.7", in: root) != nil)
        #expect(element("overview.process.6", in: root) != nil)
        #expect(element("overview.process.5", in: root) == nil)
        #expect(press(try #require(element("overview.process.8", in: root))))
        #expect(console.module == .processes)
        #expect(console.selectedPID == 8)
        console.open(.overview)
        #expect(press(try #require(element("overview.processes.all", in: root))))
        #expect(console.module == .processes)
    }

    @MainActor @Test("The secondary glance spends the same column width as the primary charts")
    func secondaryGlanceUsesColumnWidth() throws {
        let window = host(OverviewMetricGlance(model: AppModel(), storage: StorageSample(), gpu: GPUSample(),
            network: NetworkTrafficSample(), sensors: SensorSample(), power: PowerSample(), showDetails: {}),
            size: NSSize(width: 940, height: 70))
        defer { window.orderOut(nil) }
        let gpu = try #require(element("overview.glance.gpu", in: window.contentView!))
        let gpuFrame = try frame(gpu)
        print("Secondary GPU glance frame: \(gpuFrame)")
        if let glance = element("overview.glance", in: window.contentView!) {
            print("Secondary glance card frame: \(try frame(glance))")
        }
        try capture(window, name: "glance-width-probe")
        #expect(gpuFrame.width >= 160)
    }

    @MainActor private func frame(_ object: NSObject) throws -> NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        try #require(object.responds(to: selector))
        let boxed = try #require(object.value(forKey: "accessibilityFrame") as? NSValue)
        return boxed.rectValue
    }

    @MainActor @Test("Chart controls live outside Overview in one toolbar row and remain functional")
    func focusAndTimeControls() throws {
        let model = AppModel()
        let console = ConsoleModel()
        let moduleWindow = host(OverviewModule(model: model, console: console),
                                size: NSSize(width: 982, height: 638))
        let toolbarWindow = host(OverviewToolbarControls(console: console),
                                 size: NSSize(width: 520, height: 32))
        defer { moduleWindow.orderOut(nil); toolbarWindow.orderOut(nil) }
        let root = try #require(moduleWindow.contentView)
        let toolbar = try #require(toolbarWindow.contentView)
        #expect(element("overview.focus", in: root) == nil)
        #expect(element("overview.time", in: root) == nil)
        let picker = try #require(element("overview.focus", in: toolbar))
        try click(try #require(labelled("CPU", in: picker)), in: toolbarWindow)
        settle()
        #expect(element("overview.cpu", in: root) != nil)
        #expect(element("overview.memory", in: root) == nil)
        try click(try #require(labelled("Memory", in: picker)), in: toolbarWindow)
        settle()
        #expect(element("overview.cpu", in: root) == nil)
        #expect(element("overview.memory", in: root) != nil)
        try click(try #require(labelled("CPU & Memory", in: picker)), in: toolbarWindow)
        settle()
        #expect(element("overview.cpu", in: root) != nil)
        #expect(element("overview.memory", in: root) != nil)
        for range in ChartTimeWindow.allCases {
            let time = try #require(element("overview.time", in: toolbar))
            try click(try #require(labelled(range.label, in: time)), in: toolbarWindow)
            settle()
            #expect(labels(in: root).contains { $0.contains("\(range.rawValue) seconds displayed") })
        }
        #expect(scrollViews(in: root).isEmpty)
    }

    @MainActor @Test("Unavailable secondary readings are dashes, never idle zeroes", arguments: [false, true])
    func unavailableGlance(dark: Bool) throws {
        let window = host(OverviewMetricGlance(model: AppModel(), storage: StorageSample(), gpu: GPUSample(),
            network: NetworkTrafficSample(), sensors: SensorSample(),
            power: PowerSample(hasBattery: true), columns: 5, showDetails: {}),
            size: NSSize(width: 940, height: 70), dark: dark)
        defer { window.orderOut(nil) }
        for id in ["disk", "gpu", "network", "sensors", "battery"] {
            let metric = try #require(element("overview.glance.\(id)", in: window.contentView!))
            let text = labels(in: metric).joined(separator: " ")
            #expect(text.contains("—"))
            #expect(!text.contains("0%"))
            #expect(!text.contains("0 KB/s"))
        }
        try capture(window, name: "overview-unavailable-\(dark ? "dark" : "light")")
    }

    // The shipping root requests refresh on appearance. Only its explicitly
    // observational harness may run this test: registry-changing RPCs are denied
    // before the actual native window is created.
    @MainActor @Test("Shipping Overview keeps its instruments visible above scrollable evidence in both appearances",
        .enabled(if: RPCRequestPolicy.forArguments(ProcessInfo.processInfo.arguments) == .observational))
    func shippingWindowViewport() async throws {
        initializeApplication()
        try #require(DaemonClient.shared.requestPolicy == .observational)
        let model = AppModel()
        let controller = ConsoleWindowController(model: model)
        controller.show(activate: false)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .seconds(4))
        settle()
        #expect(model.system.cpu.sampled)
        #expect(model.processes.rows.count >= 5)
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.appearance = NSApp.appearance
            for (name, size) in [("compact", NSSize(width: 982, height: 720)),
                                 ("standard", NSSize(width: 1560, height: 900))] {
                window.setContentSize(size)
                try await Task.sleep(for: .milliseconds(100))
                settle()
                let root = try #require(window.contentView)
                let activeScrolls = scrollViews(in: root).filter {
                    !$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty
                }
                // The shipping workspace intentionally scrolls its process map
                // and interval evidence below the fixed-height instruments.
                // A sidebar List also scrolls; neither is an OverviewModule
                // overflow (covered separately by compactOverviewDoesNotScroll).
                let cpu = try #require(element("overview.cpu", in: root))
                let cpuRect = root.convert(window.convertFromScreen(try frame(cpu)), from: nil)
                let workspaceScrolls = activeScrolls.filter { root.convert($0.bounds, from: $0).contains(cpuRect) }
                #expect(workspaceScrolls.count == 1)
                let workspace = try #require(workspaceScrolls.first)
                #expect((workspace.documentView?.bounds.height ?? 0) > workspace.contentView.bounds.height)
                #expect(element("overview.process-map", in: root) != nil)
                for id in ["overview.cpu", "overview.memory", "overview.glance", "overview.processes"] {
                    let object = try #require(element(id, in: root))
                    let rect = root.convert(window.convertFromScreen(try frame(object)), from: nil)
                    print("\(name) \(dark ? "dark" : "light") \(id): \(rect)")
                    #expect(rect.minX >= 0)
                    #expect(rect.maxX <= root.bounds.width)
                    if root.isFlipped {
                        #expect(rect.maxY <= root.bounds.height)
                    } else {
                        #expect(rect.minY >= 0)
                    }
                }
                // The workspace reserves a compact, fixed-height instrument
                // area at both window sizes; width does not add process rows.
                let processRows = Set(nodes(in: root)
                    .compactMap { value("accessibilityIdentifier", from: $0) as? String }
                    .filter { $0.hasPrefix("overview.process.") })
                #expect(processRows.count == 3)
                try capture(window, name: "overview-\(name)-\(dark ? "dark" : "light")")
            }
        }
        #expect(DaemonClient.shared.submittedObservationalOperations.allSatisfy {
            ["ping", "snapshot", "subscribe", "events", "logs", "messages"].contains($0)
        })
    }

    @MainActor private func nodes(in root: Any) -> [NSObject] {
        guard let object = root as? NSObject else { return [] }
        return [object] + (value("accessibilityChildren", from: object) as? [Any] ?? []).flatMap { nodes(in: $0) }
    }

    @MainActor private func labels(in root: Any) -> [String] {
        nodes(in: root).flatMap { object in
            [value("accessibilityLabel", from: object) as? String,
             value("accessibilityValue", from: object) as? String].compactMap { $0 }
        }
    }

    @MainActor private func labelled(_ label: String, in root: Any) -> NSObject? {
        nodes(in: root).first { value("accessibilityLabel", from: $0) as? String == label }
    }

    @MainActor private func click(_ object: NSObject, in window: NSWindow) throws {
        let rect = window.convertFromScreen(try frame(object))
        let location = NSPoint(x: rect.midX, y: rect.midY)
        try sendSyntheticClick(at: location, in: window)
    }

    @MainActor @Test("Search filters names and command lines before applying the process cap")
    func searchBeforeCap() throws {
        let rows = [process(pid: 1, name: "not-a-match", bytes: 9_000),
                    process(pid: 2, name: "target-worker", bytes: 1_000),
                    process(pid: 3, name: "python3", bytes: 2_000, command: "python3 /fixture/target.py")]
        let console = ConsoleModel()
        let window = host(OverviewProcessPreview(model: AppModel(), rows: rows, query: " TARGET ", limit: 1, console: console),
                          size: NSSize(width: 940, height: 170))
        defer { window.orderOut(nil) }
        let root = try #require(window.contentView)
        #expect(element("overview.process.3", in: root) != nil)
        #expect(element("overview.process.2", in: root) == nil)
        #expect(element("overview.process.1", in: root) == nil)
    }

    private func process(pid: Int32, name: String, bytes: Int64, command: String? = nil) -> ProcessRow {
        ProcessRow(id: pid, pid: pid, ppid: 1, pgid: pid, uid: 501, user: "fixture", name: name,
                   commandLine: command ?? name, cpuPercent: 12, residentBytes: bytes,
                   ports: [], startSignature: "fixture-\(pid)", stateField: "R")
    }

    @MainActor private func press(_ object: NSObject) -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        let action = unsafeBitCast(object.method(for: selector), to: Action.self)
        return action(object, selector)
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
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    @MainActor private func scrollViews(in root: NSView) -> [NSScrollView] {
        (root as? NSScrollView).map { [$0] } ?? root.subviews.flatMap { scrollViews(in: $0) }
    }

    @MainActor private func host<Content: View>(_ view: Content, size: NSSize, dark: Bool = false) -> NSWindow {
        initializeApplication()
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.appearance = window.appearance
        window.contentView = hosting
        window.backgroundColor = .windowBackgroundColor
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)
        settle()
        return window
    }

    @MainActor private func initializeApplication() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        if !NSApp.isRunning { NSApp.finishLaunching() }
        _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"),
                          with: NSNumber(value: true), with: "AXEnhancedUserInterface")
    }

    @MainActor private func settle() {
        for _ in 0..<12 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.025))
        }
    }

    @MainActor private func capture(_ window: NSWindow, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["FLEET_OVERVIEW_CAPTURE_DIR"] else { return }
        let view = try #require(window.contentView?.superview)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        bitmap.size = view.bounds.size
        view.setNeedsDisplay(view.bounds)
        window.displayIfNeeded()
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
