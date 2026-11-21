import AppKit
import Testing

@MainActor func sendSyntheticClick(at location: NSPoint, in window: NSWindow) throws {
    let events = try [NSEvent.EventType.leftMouseDown, .leftMouseUp].map { type in
        try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
    }
    let release = PendingRelease(events[1])
    let timer = Timer(timeInterval: 0.05, repeats: false) { _ in
        MainActor.assumeIsolated { release.postIfUnsent() }
    }
    RunLoop.main.add(timer, forMode: .common)
    window.sendEvent(events[0])
    timer.invalidate()
    if release.claim() { window.sendEvent(events[1]) }
}

@MainActor private final class PendingRelease {
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
