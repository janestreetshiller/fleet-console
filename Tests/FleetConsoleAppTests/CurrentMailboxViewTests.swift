import AppKit
import SwiftUI
import Testing
import FleetCore
@testable import FleetConsoleApp

@Suite(.serialized)
struct CurrentMailboxViewTests {
    @MainActor @Test("Inbox hides old resolved history, History restores access, and offline state is not an empty success")
    func inboxHistoryAndUnavailableStates() throws {
        let model = AppModel()
        DaemonClient.shared.stop()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.finishLaunching()
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let hosting = NSHostingView(rootView: AgentsMailboxSheet(model: model)
            .accessibilityElement(children: .contain))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 560, height: 520),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        settle()
        let old = Date().addingTimeInterval(-90 * 24 * 3600)
        let archived = AgentMessage(id: 7, agent: "demo", kind: .question, body: "Archived question", createdAt: old,
                                    needsReply: true, reply: "Resolved", repliedAt: old, seenAt: old)
        model.apply(Snapshot(daemon: DaemonInfo(version: "test", pid: 0, startedAt: Date()), messages: [archived]))
        model.connected = true
        settle()
        #expect(element("mailbox.empty", in: hosting) != nil)
        #expect(!labels(in: hosting).contains(where: { $0.contains("Archived question") }))
        let history = try #require(element("mailbox.history", in: hosting))
        #expect(press(history))
        settle()
        #expect(labels(in: hosting).contains(where: { $0.contains("Archived question") }))
        #expect(model.messageHistory == [archived])
        let historyAgain = try #require(element("mailbox.history", in: hosting))
        #expect(press(historyAgain))
        model.connected = false
        settle()
        #expect(element("mailbox.unavailable", in: hosting) != nil)
        #expect(element("mailbox.empty", in: hosting) == nil)
        #expect(!labels(in: hosting).contains(where: { $0.contains("Archived question") }))
        #expect(model.messageHistory == [archived])
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

    @MainActor private func labels(in root: Any) -> [String] {
        guard let object = root as? NSObject else { return [] }
        let own = ["accessibilityLabel", "accessibilityValue"].compactMap { value($0, from: object) as? String }
        return own + (value("accessibilityChildren", from: object) as? [Any] ?? []).flatMap { labels(in: $0) }
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
