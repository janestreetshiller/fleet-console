import SwiftUI
import AppKit
import FleetCore

// The first-launch welcome.
//
// One window, shown once: a menu-bar app that opens a console window on first
// launch has buried its own premise — the app *is* the menu-bar item, and the
// welcome exists to say that, show what the console looks like, and get out of
// the way. The pitch is one sentence, then a live RetroGauge sweep — the
// instrument a new user has not met yet, doing the one thing that sells it.
//
// Shown once, persisted in UserDefaults. The animation can be skipped at any
// time (the button works from the first frame, and Escape dismisses), and the
// *option to suppress the welcome entirely* is premium — the onboarding is
// part of what a trial evaluates. See FleetCore/License.swift.
//
// Colour and type: every visible value is a token — ConsoleColor, ConsoleFont,
// ConsoleMetrics, StatusTone. The audit's job is to keep it that way.

/// First-launch state. Kept in one tiny type because three places need the
/// same answer: the delegate (should it open), the view (did it already), and
/// the menu (reset for support calls).
@MainActor
enum WelcomeState {
    static let defaults = UserDefaults.standard
    static let shownKey = "fleetconsole.welcomeShown"

    static var hasShown: Bool {
        get { defaults.bool(forKey: shownKey) }
        set { defaults.set(newValue, forKey: shownKey) }
    }

    /// Whether the welcome should appear for this launch. Reading it *marks*
    /// the welcome as shown, so it is called exactly once, by the delegate —
    /// a flag that two call sites both check is a welcome that appears twice.
    static func consumePending() -> Bool {
        defer { hasShown = true }
        return !hasShown
    }

    static func reset() { hasShown = false }
}

// MARK: - Window controller

/// The welcome's AppKit shell: a titled, hidden-titlebar window whose close
/// button and the view's own dismiss are the same exit. `isReleasedWhenClosed
/// = false` so the controller can hand the window back on replay without
/// rebuilding it, and `windowWillClose` nils the reference so a closed window
/// is never re-shown as a live one.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = WelcomeView(model: model) { [weak self] in self?.close() }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 560, height: 420)),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Welcome to FleetConsole"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = hosting
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }

    // The window's close button and the view's own dismiss are the same exit;
    // without this the AppKit close would strand the controller's reference.
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

// MARK: - View

struct WelcomeView: View {
    @Bindable var model: AppModel
    let dismiss: () -> Void

    /// The skip option is the premium feature; the *Skip button* below is not
    /// — skipping one showing and suppressing the welcome for every launch are
    /// different asks, and only the second is gated.
    @AppStorage("fleetconsole.skipWelcome") private var skipWelcome = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            stage
            Hairline()
            footer
        }
        .frame(width: 560, height: 420)
        .sketchSubstrate(seed: 0.61, grainSeed: 61)
        // Escape dismisses; the animation's own skip affordance is the button.
        .onExitCommand { dismiss() }

    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Welcome to FleetConsole")
                .font(ConsoleFont.cardTitle)
            Spacer()
            ConsoleBadge(text: "MIT · OPEN SOURCE", tone: .neutral)
        }
        .padding(.horizontal, ConsoleMetrics.gutter)
        .padding(.vertical, ConsoleMetrics.panelInset)
    }

    private var stage: some View {
        VStack(alignment: .leading, spacing: ConsoleMetrics.sectionGap) {
            Text("See what your Mac is doing.")
                .font(ConsoleFont.heroTitle)
            Text("Live metrics and background work, one click from the menu bar.")
                .font(ConsoleFont.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Explore CPU and memory over time", systemImage: "chart.xyaxis.line")
            Label("Inspect processes, services and leases", systemImage: "list.bullet")
            Label("Link more computers through the device add-on", systemImage: "desktopcomputer")
        }
        .font(ConsoleFont.body)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, ConsoleMetrics.gutter)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Skip") { dismiss() }
                .buttonStyle(.link)
                .font(ConsoleFont.body)

            if model.license.isUnlocked(.skipWelcomeAnimation) {
                Toggle("Don't show again", isOn: $skipWelcome)
                    .toggleStyle(.checkbox)
                    .font(ConsoleFont.caption)
                    .controlSize(.small)
            }

            Spacer()
            Button("Open Console") { dismiss(); openConsole() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, ConsoleMetrics.gutter)
        .padding(.vertical, ConsoleMetrics.panelInset)
    }


    private func openConsole() {
        NotificationCenter.default.post(name: ConsoleCommand.showHome, object: nil)
    }
}
