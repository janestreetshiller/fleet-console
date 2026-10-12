import AppKit
import Testing

/// Sends a press and release to `window` at `location`, in window coordinates.
///
/// On macOS 15 a SwiftUI button is an AppKit control, and a control tracks the
/// press in a nested event loop that returns only once the release arrives. A
/// release sent after the press returns never reaches that loop, and the test
/// hangs until CI kills it. So the release is armed on a timer that fires inside
/// the tracking loop; where nothing tracks the press, it is sent directly.
@MainActor func sendSyntheticClick(at location: NSPoint, in window: NSWindow) throws {
    let events = try [NSEvent.EventType.leftMouseDown, .leftMouseUp].map { type in
        try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
    }
    let release = PendingRelease(events[1])
    let timer = Timer(timeInterval: 0.05, repeats: false) { _ in release.postIfUnsent() }
    RunLoop.main.add(timer, forMode: .common)
    window.sendEvent(events[0])
    timer.invalidate()
    if release.claim() { window.sendEvent(events[1]) }
}

/// The release, sent exactly once: posted to a tracking loop, or dispatched
/// after a press nothing tracked. Touched only on the main thread.
private final class PendingRelease: @unchecked Sendable {
    private let event: NSEvent
    private var sent = false

    init(_ event: NSEvent) { self.event = event }

    func claim() -> Bool {
        defer { sent = true }
        return !sent
    }

    func postIfUnsent() {
        if claim() { NSApp.postEvent(event, atStart: false) }
    }
}
