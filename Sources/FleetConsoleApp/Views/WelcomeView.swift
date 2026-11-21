import SwiftUI
import AppKit
import FleetCore

@MainActor
enum WelcomeState {
    static let defaults = UserDefaults.standard
    static let shownKey = "fleetconsole.welcomeShown"

    static var hasShown: Bool {
        get { defaults.bool(forKey: shownKey) }
        set { defaults.set(newValue, forKey: shownKey) }
    }

    static func consumePending() -> Bool {
        defer { hasShown = true }
        return !hasShown
    }

    static func reset() { hasShown = false }
}

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

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct WelcomeView: View {
    @Bindable var model: AppModel
    let dismiss: () -> Void

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
