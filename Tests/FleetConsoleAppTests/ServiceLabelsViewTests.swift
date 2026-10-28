import AppKit
import SwiftUI
import Testing
import FleetCore
@testable import FleetConsoleApp

@Suite(.serialized)
struct ServiceLabelsViewTests {
    @Test("The native name and tag editor fits inside the Services popover")
    @MainActor
    func editorFitsPopover() {
        _ = NSApplication.shared
        let scratch = ProcessInfo.processInfo.environment["TMPDIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        let path = scratch.appendingPathComponent("fleet-label-editor-\(UUID().uuidString).json")
        let labels = ServiceLabelsStore(path: path)
        let service = ServiceRecord(friendlyName: "worker-api", ownerAgent: "claude",
                                    purpose: "serve requests", command: ["python3"], cwd: "/fixture/project",
                                    leaseExpiresAt: Date().addingTimeInterval(3600), leaseTTLSec: 3600)
        let host = NSHostingView(rootView: ServiceLabelEditor(service: service, labels: labels))
        let size = host.fittingSize
        #expect(size.width > 200)
        #expect(size.width <= FleetMetrics.popoverWidth)
        #expect(size.height > 150)
        #expect(size.height <= FleetMetrics.sectionMaxHeight)
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }

    @Test("Each service's native edit button opens a keyboard-accessible label editor")
    @MainActor
    func editButtonOpensEditor() throws {
        let scratch = ProcessInfo.processInfo.environment["TMPDIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        let path = scratch.appendingPathComponent("fleet-label-editor-\(UUID().uuidString).json")
        let labels = ServiceLabelsStore(path: path)
        let service = ServiceRecord(id: "service-a", friendlyName: "worker-api", ownerAgent: "claude",
                                    purpose: "serve requests", command: ["python3"], cwd: "/fixture/project",
                                    leaseExpiresAt: Date().addingTimeInterval(3600), leaseTTLSec: 3600)
        let window = host(ServiceLabelEditButton(service: service, labels: labels))
        defer { window.orderOut(nil) }
        let button = try #require(element("service.labels.edit.service-a", in: window.contentView!))
        #expect(value("accessibilityLabel", from: button) as? String == "Edit name and tag for worker-api")
        #expect(press(button))
        settle()
        let editorWindow = try #require(NSApp.windows.first { window in
            guard let content = window.contentView else { return false }
            return element("service.labels.name", in: content) != nil
        })
        let input = try #require(element("service.labels.name", in: editorWindow.contentView!))
        #expect(value("accessibilityLabel", from: input) as? String == "Friendly name")
        #expect(element("service.labels.color", in: editorWindow.contentView!) != nil)
        let cancel = try #require(element("service.labels.cancel", in: editorWindow.contentView!))
        #expect(press(cancel))
        settle()
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }

    @MainActor private func host<Content: View>(_ view: Content) -> NSWindow {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.finishLaunching()
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let hosting = NSHostingView(rootView: VStack { view }
            .frame(width: 480, height: 350)
            .accessibilityElement(children: .contain))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 350),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.backgroundColor = .windowBackgroundColor
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)
        settle()
        return window
    }

    @MainActor private func settle() {
        for _ in 0..<8 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.025))
        }
    }

    // SwiftUI AccessibilityNode uses the informal NSObject AX contract, not
    // NSAccessibilityProtocol conformance. The driver must traverse both.
    @MainActor private func element(_ id: String, in root: Any) -> NSObject? {
        guard let accessible = root as? NSObject else { return nil }
        if value("accessibilityIdentifier", from: accessible) as? String == id { return accessible }
        for child in value("accessibilityChildren", from: accessible) as? [Any] ?? [] {
            if let found = element(id, in: child) { return found }
        }
        return nil
    }

    @MainActor private func value(_ getter: String, from object: NSObject) -> Any? {
        let selector = NSSelectorFromString(getter)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    @MainActor private func press(_ object: NSObject) -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        let action = unsafeBitCast(object.method(for: selector), to: Action.self)
        return action(object, selector)
    }

    @Test("Color tags identify a personal tag, never a health verdict")
    @MainActor
    func tagSemantics() {
        for color in ServiceTagColor.allCases {
            let tag = ServiceColorTag(color: color)
            #expect(tag.accessibilityText == "\(color.label) tag")
        }
    }
}
