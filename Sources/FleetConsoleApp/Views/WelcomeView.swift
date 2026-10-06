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

private struct WelcomeView: View {
    @Bindable var model: AppModel
    let dismiss: () -> Void

    /// 0 → 1 while the needle sweeps. Drives the gauge, the ring and the
    /// caption so the three never disagree about where the intro is.
    @State private var phase: Double = 0
    @State private var entered = false

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
        .onAppear {
            withAnimation(ConsoleMotion.welcomeEntrance) { entered = true }
            startSweep()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Welcome to FleetConsole")
                .font(ConsoleFont.cardTitle)
            Spacer()
            ConsoleBadge(text: licenseBadge, tone: licenseTone)
        }
        .padding(.horizontal, ConsoleMetrics.gutter)
        .padding(.vertical, ConsoleMetrics.panelInset)
    }

    /// The product pitch: one sentence about what the app is, then the gauge.
    /// A feature list here would be a store page; the console itself is the
    /// feature list, one click away.
    private var stage: some View {
        VStack(spacing: ConsoleMetrics.sectionGap) {
            Text("Your whole fleet, in the menu bar.")
                .font(ConsoleFont.heroTitle)
                .multilineTextAlignment(.center)

            Text("FleetConsole watches the daemons, leases and processes you "
                 + "already run — and puts the evidence one click from the clock.")
                .font(ConsoleFont.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            gaugeStage
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, ConsoleMetrics.gutter)
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 6)
    }

    /// The live sweep: a real RetroGauge runs 0 → 78% → 12% inside a breathing
    /// ring. The needle's value is the animation's phase — not a recording of
    /// the instrument, the instrument.
    private var gaugeStage: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: phase)
                .stroke(StatusTone.warn.ink,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 216, height: 216)
                .opacity(0.6)

            RetroGauge(value: gaugeValue, tone: gaugeTone, caption: "CPU",
                       readout: ConsoleFmt.utilPercent(gaugeValue))
                .frame(width: 184, height: 184)
        }
        .frame(height: 240)
    }

    /// The sweep's story: spin up, hold at working load, settle. Piecewise so
    /// the needle spends most of the intro in the band that shows off the
    /// gauge's warning colour.
    private var gaugeValue: Double? {
        switch phase {
        case ..<0.4: return phase / 0.4 * 0.78
        case ..<0.75: return 0.78
        default: return 0.78 - (phase - 0.75) / 0.25 * 0.66
        }
    }

    private var gaugeTone: StatusTone {
        SystemThresholds.utilization(gaugeValue ?? 0)
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

    private var licenseBadge: String {
        switch model.license.status {
        case .licensed: return "LICENSED"
        case .trial(let days): return "TRIAL · \(days)d"
        case .expired: return "TRIAL OVER"
        }
    }

    private var licenseTone: StatusTone {
        switch model.license.status {
        case .licensed: return .good
        case .trial: return .neutral
        case .expired: return .warn
        }
    }

    private func startSweep() {
        withAnimation(ConsoleMotion.welcomeSweep) { phase = 1 }
    }

    private func openConsole() {
        NotificationCenter.default.post(name: ConsoleCommand.showHome, object: nil)
    }
}
