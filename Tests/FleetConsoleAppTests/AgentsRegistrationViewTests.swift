import AppKit
import SwiftUI
import Vision
import Foundation
import Testing
import FleetCore
@testable import FleetConsoleApp

@Suite(.serialized)
struct AgentsRegistrationViewTests {
    @MainActor @Test("An empty roster offers inline registration and publishes the saved ID")
    func inlineRegistration() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registration = AgentRegistrationModel(fileURL: directory.appendingPathComponent("roster.json"))
        let window = host(VStack(alignment: .leading, spacing: 0) {
            AgentRosterSection(profiles: [], registration: registration)
            Spacer(minLength: 0)
        })
        defer { window.orderOut(nil) }
        try click("Register Agent ID", in: window)
        #expect(try text(in: window).contains("Cancel"))
        registration.agentID = "Worker-01"
        settle()
        try click("Register", in: window)
        #expect(registration.registeredIDs == ["Worker-01"])
        #expect(try text(in: window).contains("Worker-01"))
        #expect(try text(in: window).contains("Idle"))
        #expect(try AgentRegistrationStore(fileURL: directory.appendingPathComponent("roster.json")).load() == ["Worker-01"])
        try capture(window, name: "inline-registration-light")
    }

    @MainActor @Test("Duplicate errors remain visible and Cancel closes the inline form", arguments: [false, true])
    func duplicateErrorAndCancel(dark: Bool) throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registration = AgentRegistrationModel(fileURL: directory.appendingPathComponent("roster.json"))
        registration.agentID = "worker"
        #expect(registration.register())
        let window = host(VStack(alignment: .leading, spacing: 0) {
            AgentRosterSection(profiles: [], registration: registration)
            Spacer(minLength: 0)
        }, dark: dark)
        defer { window.orderOut(nil) }
        try click("Register Agent ID", in: window)
        registration.agentID = "worker"
        settle()
        try click("Register", in: window)
        #expect(registration.registeredIDs == ["worker"])
        #expect(registration.agentID == "worker")
        #expect(registration.statusIsError)
        #expect(try text(in: window).contains("already registered"))
        try capture(window, name: "duplicate-registration-\(dark ? "dark" : "light")")
        try click("Cancel", in: window)
        #expect(registration.agentID.isEmpty)
        #expect(try !text(in: window).contains("Cancel"))
    }

    @MainActor @Test("Return submits the focused Agent ID field")
    func returnSubmitsRegistration() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registration = AgentRegistrationModel(fileURL: directory.appendingPathComponent("roster.json"))
        let window = host(VStack(alignment: .leading, spacing: 0) {
            AgentRosterSection(profiles: [], registration: registration)
            Spacer(minLength: 0)
        })
        defer { window.orderOut(nil) }
        try click("Register Agent ID", in: window)
        #expect(window.firstResponder is NSTextView)
        registration.agentID = "via-return"
        settle()
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        window.sendEvent(event)
        settle()
        #expect(registration.registeredIDs == ["via-return"])
        #expect(try text(in: window).contains("Idle"))
    }

    @MainActor @Test("The crowded glance fits 300pt without scrolling and routes every overflow action", arguments: [false, true])
    func boundedGlance(dark: Bool) throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLEET_TEST_TMPDIR"]
            ?? FileManager.default.temporaryDirectory.path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registration = AgentRegistrationModel(fileURL: directory.appendingPathComponent("roster.json"))
        for index in 0..<8 {
            registration.agentID = "worker-\(index)"
            #expect(registration.register())
        }
        let sessions = (0..<4).map { AgentSession(id: "session-\($0)", tool: "codex", pid: Int32($0 + 100),
            project: "/Users/fixture/project-\($0)", cpuPct: 99, memMB: 999) }
        var actions: [String] = []
        let window = host(AgentGlanceContent(profiles: [], sessions: sessions, registration: registration,
            pendingReplyCount: 3, messageCount: 9,
            register: { actions.append("register") }, mailbox: { actions.append("mailbox") },
            manage: { actions.append("manage") }).frame(width: 480, height: 300), dark: dark)
        defer { window.orderOut(nil) }
        #expect(window.contentView?.bounds.height == 300)
        #expect(scrollViews(in: window.contentView!).isEmpty)
        let visible = try text(in: window)
        #expect(visible.contains("8 agent IDs"))
        #expect(visible.contains("4 detected"))
        // The roster is a one-line count on the tab; every entry is behind Show all.
        #expect(visible.contains("Show all 12"))
        #expect(!visible.contains("99%"))
        #expect(!visible.contains("999 MB"))
        try capture(window, name: "bounded-agents-\(dark ? "dark" : "light")")
        try click("Register Agent ID", in: window)
        try click("3 waiting", in: window)
        try click("Show all 12", in: window)
        #expect(actions == ["register", "mailbox", "manage"])
    }

    @MainActor private func scrollViews(in root: NSView) -> [NSScrollView] {
        (root as? NSScrollView).map { [$0] } ?? root.subviews.flatMap { scrollViews(in: $0) }
    }

    @MainActor private func host<Content: View>(_ view: Content, dark: Bool = false) -> NSWindow {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        if !NSApp.isRunning { NSApp.finishLaunching() }
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
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

    @MainActor private func settle() {
        for _ in 0..<8 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.025))
        }
    }

    @MainActor private func bitmap(_ window: NSWindow) throws -> NSBitmapImageRep {
        let view = try #require(window.contentView?.superview)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        bitmap.size = view.bounds.size
        view.setNeedsDisplay(view.bounds)
        window.displayIfNeeded()
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    @MainActor private func observations(in window: NSWindow) throws -> [VNRecognizedTextObservation] {
        let image = try #require(bitmap(window).cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return request.results ?? []
    }

    @MainActor private func text(in window: NSWindow) throws -> String {
        try observations(in: window).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Public native event dispatch, scoped to this offscreen test window. Vision
    /// locates rendered controls because SwiftUI's AX tree is lazy without an AX client.
    @MainActor private func click(_ title: String, in window: NSWindow) throws {
        let rendered = try observations(in: window)
        try capture(window, name: "before-\(title.replacingOccurrences(of: " ", with: "-"))")

        let candidate = try #require(rendered.compactMap { $0.topCandidates(1).first }.first {
            $0.string.contains(title) && (title != "Register"
                || ($0.string.split(whereSeparator: \.isWhitespace).contains("Register")
                    && !$0.string.contains("Agent ID")))
        })
        let range = try #require(candidate.string.range(of: title))
        let box = try #require(try candidate.boundingBox(for: range)).boundingBox
        let view = try #require(window.contentView)
        let point = NSPoint(x: box.midX * view.bounds.width,
                            y: (view.isFlipped ? 1 - box.midY : box.midY) * view.bounds.height)
        let location = view.convert(point, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            window.sendEvent(event)
        }
        settle()
    }

    @MainActor private func capture(_ window: NSWindow, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["FLEET_AGENTS_CAPTURE_DIR"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let data = try #require(bitmap(window).representation(using: .png, properties: [:]))
        try data.write(to: url.appendingPathComponent("\(name).png"))
    }
}
