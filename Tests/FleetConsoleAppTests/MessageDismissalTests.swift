import AppKit
import SwiftUI
import Testing
import FleetCore
@testable import FleetConsoleApp

struct MessageDismissalTests {
    @Test("Dismissals survive a relaunch and stay bounded")
    func persistedAndBounded() throws {
        let suite = "dismissal-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = MessageDismissals(defaults: defaults)
        first.insert([4, 9])
        let relaunched = MessageDismissals(defaults: defaults)
        #expect(relaunched.contains(4) && relaunched.contains(9))
        #expect(!relaunched.contains(5))
        relaunched.insert(Array(10..<2_510))
        let bounded = MessageDismissals(defaults: defaults)
        #expect(!bounded.contains(4))
        #expect(bounded.contains(2_509))
    }

    @MainActor @Test("The Agents tab dismisses one message or clears them all")
    func glanceRoutesDismissals() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        if !NSApp.isRunning { NSApp.finishLaunching() }
        _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"),
                          with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let messages = [AgentMessage(id: 7, agent: "claude", body: "renewed the tunnel lease"),
                        AgentMessage(id: 8, agent: "codex", kind: .question, body: "restart search?", needsReply: true)]
        var dismissed: [[Int64]] = []
        let view = AgentGlanceContent(profiles: [], sessions: [],
            registration: AgentRegistrationModel(fileURL: directory.appendingPathComponent("roster.json")),
            pendingReplyCount: 1, messageCount: 2, messages: messages,
            register: {}, mailbox: {}, manage: {}, dismiss: { dismissed.append($0) })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view.frame(width: 480, height: 300))
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<12 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.025)) }
        #expect(press("agents.message.dismiss.7", in: window.contentView!))
        #expect(press("agents.messages.clear", in: window.contentView!))
        #expect(dismissed == [[7], [7, 8]])
    }

    @MainActor private func press(_ id: String, in root: Any) -> Bool {
        guard let object = element(id, in: root) else { return false }
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector)
    }

    @MainActor private func element(_ id: String, in root: Any) -> NSObject? {
        guard let object = root as? NSObject else { return nil }
        if object.responds(to: NSSelectorFromString("accessibilityIdentifier")),
           object.value(forKey: "accessibilityIdentifier") as? String == id { return object }
        let children = (object.responds(to: NSSelectorFromString("accessibilityChildren"))
            ? object.value(forKey: "accessibilityChildren") as? [Any] : nil) ?? []
        for child in children { if let found = element(id, in: child) { return found } }
        return nil
    }
}
