#if FLEET_SURFACE_RENDERER
import AppKit
import SwiftUI
import FleetCore

// Renders every FleetConsole surface to PNG.
//
// This lives in the app target rather than in a throwaway package beside it,
// because the console's views need `AppModel`, `ConsoleModel`, `ChromeTools` and
// the probes — the whole target. Reaching them from outside would mean
// symlinking the target into a second package and keeping the two in step, and a
// design sheet that drifts from the app is worse than no sheet.
//
// It is compiled only when `FLEET_SURFACE_RENDERER` is defined, which only
// `Scripts/surface-sheet.sh` does. `Scripts/build-app.sh` does not, so none of
// this — including the fixtures — is in the shipped binary.
//
// The fixtures below are the point. Rendering the *live* fleet gives whatever
// happens to be running, which on a quiet machine is six empty states; a sheet
// is meant to show each surface carrying its full vocabulary at once — every
// status tone, evidence in all four of its separate facts, an expiring lease, a
// crash, an unmanaged listener.

@MainActor
enum SurfaceRenderer {
    nonisolated static let flag = "--render-surfaces"

    /// The console window's canonical size, and the popover's own width.
    private static let popoverWidth: CGFloat = FleetMetrics.popoverWidth

    // MARK: - Entry point

    static let churnFlag = "--measure-churn"

    static func runIfRequested() -> Bool {
        if CommandLine.arguments.contains(churnFlag) {
            measureChurn()
            return true
        }
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }
        guard index + 1 < arguments.count else {
            FileHandle.standardError.write(Data("\(flag) needs an output directory\n".utf8))
            exit(2)
        }
        let out = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        // Offscreen windows still need a running NSApplication for layout,
        // fonts and appearance resolution — but not an activated one.
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()

        render(into: out)
        return true
    }

    // MARK: - Churn

    /// Counts how many times the live probes publish over a fixed window.
    ///
    /// "Do not rebuild the menu when nothing changed" is a claim, and a claim
    /// about a running app is worth exactly what it is measured at. This boots
    /// the real `AppModel` — real timers, real `ps`, real `netstat` — puts an
    /// `withObservationTracking` loop on each published surface, and prints how
    /// often each one actually fired.
    ///
    /// The interesting number is `routing`. Its snapshot carries the whole
    /// interface inventory and its `checkedAt` moves on every pass, so a plain
    /// `!=` would publish on every single refresh forever. `sameContent(as:)`
    /// is what makes the expected count **0** on a machine whose network is not
    /// changing — and 0 is only meaningful next to a `processes` count that is
    /// non-zero, which proves the harness is watching a live model rather than a
    /// dead one.
    private static func measureChurn() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()

        let seconds = CommandLine.arguments.firstIndex(of: churnFlag)
            .flatMap { $0 + 1 < CommandLine.arguments.count ? Double(CommandLine.arguments[$0 + 1]) : nil }
            ?? 45

        let model = AppModel()
        let counts = Counter()

        watch("routing", counts) { _ = model.network.routing }
        watch("processes", counts) { _ = model.processes.rows }
        watch("menu-bar", counts) {
            _ = model.fleetMeters; _ = model.fleetAlert; _ = model.fleetTint; _ = model.fleetTooltip
        }

        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.25))
        }

        let interval = model.settings.intervals
        print("churn over \(Int(seconds))s")
        print("  network probe ran ~\(Int(seconds / interval.clampedNetworkRefresh))x, "
              + "process sampler ~\(Int(seconds / interval.clampedProcessSample))x")
        for key in ["routing", "processes", "menu-bar"] {
            print("  \(key) published \(counts.value(key))x")
        }
        exit(0)
    }

    /// Re-arms itself on every change, counting as it goes. A static method rather
    /// than three mutually-recursive local functions: `onChange` is `@Sendable`, and
    /// a local function captured into it is not.
    private static func watch(_ key: String, _ counts: Counter,
                              _ read: @escaping @MainActor () -> Void) {
        withObservationTracking(read, onChange: {
            Task { @MainActor in
                counts.bump(key)
                watch(key, counts, read)
            }
        })
    }

    @MainActor
    private final class Counter {
        private var counts: [String: Int] = [:]
        func bump(_ key: String) { counts[key, default: 0] += 1 }
        func value(_ key: String) -> Int { counts[key] ?? 0 }
    }

    // MARK: - The run

    private static func render(into out: URL) {
        let model = AppModel()
        // Only aggregate system telemetry stays live. Process and network
        // identity collectors are disabled in this explicit fixture mode.
        DaemonClient.shared.stop()
        model.network.ethernet = EthernetStatus(interface: "en0", connected: true,
            ipv4: "198.51.100.10", linkSpeed: "1000baseT", duplex: "full")
        model.network.wifi = WiFiStatus(interface: "en1", poweredOn: true, connected: true,
            ssid: "Demo Wi-Fi", rssi: -55, noise: -90, transmitRateMbps: 866,
            channel: "36", ipv4: "198.51.100.11")
        model.network.tailscale = TailscaleUIStatus(installed: true, running: true,
            backendState: "Running", deviceName: "demo-mac", dnsName: "demo.example.invalid",
            ipv4: "203.0.113.42", tailnet: "demo.example.invalid", peerCount: 3, onlinePeerCount: 2)
        let fixture = Fixtures.snapshot()
        // The client-local roster is separate from Snapshot. Never let fixture
        // views fall back to the operator's persistent singleton.
        let rosterFile = out.appendingPathComponent(".fixture-agents-\(UUID().uuidString).json")
        do {
            try JSONEncoder().encode(["claude", "codex", "operator"])
                .write(to: rosterFile, options: .withoutOverwriting)
        } catch { fatalError("Cannot create isolated fixture roster: \(error)") }
        defer { try? FileManager.default.removeItem(at: rosterFile) }
        let registration = AgentRegistrationModel(fileURL: rosterFile)

        // A declared VLAN segment, so the sheet shows the segment vocabulary
        // rather than the absence of it. Same rule as every other fixture here:
        // rendering only what happens to be true on the build machine gives a
        // sheet of empty states, and the segment surfaces are exactly the ones
        // that render *nothing* until something is declared.
        //
        // It goes in through `adopt` — the config path — rather than by
        // constructing a `NetworkSegment` directly, so what the sheet proves is
        // the chain a real `config.json` takes.
        //
        // Always use synthetic declarations, never the operator's configured
        // network names, subnets or gateways. Live network inspection belongs
        // to the running app, not to the public fixture sheet.
        VLANRegistry.shared.adopt(Fixtures.segments)

        for appearance in Appearance.allCases {
            NSApp.appearance = NSAppearance(named: appearance.name)
            renderMenuBar(model: model, appearance: appearance, into: out)
            renderPopover(model: model, fixture: fixture, registration: registration, appearance: appearance, into: out)
            renderConsole(model: model, fixture: fixture, appearance: appearance, into: out)
            renderTaskComposer(registration: registration, appearance: appearance, into: out)
            renderStandalone(AnyView(DeviceManagementView(model: model)), name: "device-management",
                             size: NSSize(width: 600, height: 650), appearance: appearance, into: out)
            renderStandalone(AnyView(WelcomeView(model: model, dismiss: {})), name: "welcome",
                             size: NSSize(width: 560, height: 420), appearance: appearance, into: out)
        }
    }

    private static func renderStandalone(_ view: AnyView, name: String, size: NSSize,
                                         appearance: Appearance, into out: URL) {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance.name)
        hosting.appearance = window.appearance
        window.contentView = hosting
        window.backgroundColor = .windowBackgroundColor
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)
        settle(turns: 40)
        capture(window, to: out.appendingPathComponent("\(name)-\(appearance.rawValue).png"))
        window.orderOut(nil)
    }

    /// The Task Composer window on its own — a surface the sheet should prove
    /// renders without defects (the assign picker, the plate labels, the launch
    /// footer) before it ever reaches a launch.
    private static func renderTaskComposer(registration: AgentRegistrationModel, appearance: Appearance, into out: URL) {
        let roster = ["claude", "codex", "operator"].map { AgentProfile(id: $0) }
        let composer = TaskComposerModel(agentProfiles: roster, registration: registration)
        composer.taskName = "embed index"
        composer.ownerAgent = "claude"
        composer.purpose = "local api for triage"
        composer.command = "python3 -m http.server"
        composer.cwd = Fixtures.homePath
        composer.leaseMinutes = 120
        composer.port = "8787"

        let hosting = NSHostingView(rootView: TaskComposerView(model: composer, dismiss: {}))
        hosting.appearance = NSAppearance(named: appearance.name)
        hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 560)
        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance.name)
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)
        let fitted = hosting.fittingSize
        window.setContentSize(NSSize(width: 480, height: max(fitted.height, 560)))
        settle(turns: 6)
        capture(window, to: out.appendingPathComponent("task-composer-\(appearance.rawValue).png"))
        window.orderOut(nil)
    }

    /// Apply a state change with animation suppressed. Every surface here is
    /// reached by mutating `ConsoleModel`/`ChromeTools`, and each of those
    /// mutations animates — a module cross-fade, a panel slide. Captured
    /// mid-flight the result is two frames composited into one backing store,
    /// which is what put a doubled, offset "Files" in the panel header.
    private static func mutate(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }

    /// Turn the run loop so SwiftUI lays out, then reassert the synthetic
    /// snapshot and turn it again so the fixture is what gets drawn.
    private static func hold(_ model: AppModel, _ fixture: Snapshot, turns: Int = 30) {
        settle(turns: max(turns, 30))
        mutate { model.apply(fixture) }
        // The connection banner and the titlebar pill read these directly rather
        // than inferring them from the snapshot, so a sheet rendered with the
        // subscription deliberately shut down would otherwise show every surface
        // wearing a red "controller offline" pill.
        model.connected = true
        model.connectionError = nil
        model.lastSnapshotAt = fixture.generatedAt
        settle(turns: 3)
    }

    enum Appearance: String, CaseIterable {
        case light, dark
        var name: NSAppearance.Name { self == .light ? .aqua : .darkAqua }
    }

    // MARK: - Menu bar

    /// The status item on a strip of menu bar, drawn through the same
    /// `MenuBarItemController.render` the live item uses: once with nothing to
    /// act on, once with an attention count beside the meters.
    private static func renderMenuBar(model: AppModel, appearance: Appearance, into out: URL) {
        let states: [(String, String, StatusTone?)] = [("clear", "", nil), ("alert", "!3", .warn)]
        for (name, alert, tint) in states {
            let strip = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            strip.wantsLayer = true
            strip.layer?.backgroundColor = (appearance == .light
                ? NSColor(white: 0.93, alpha: 1) : NSColor(white: 0.16, alpha: 1)).cgColor
            let button = NSButton(frame: .zero)
            button.isBordered = false
            button.imagePosition = .imageLeading
            MenuBarItemController.render(.init(meters: model.fleetMeters, alert: alert, tint: tint,
                                               tooltip: "", accessibilityLabel: "FleetConsole"),
                                         on: button)
            button.sizeToFit()
            button.setFrameOrigin(NSPoint(x: (strip.bounds.width - button.frame.width) / 2,
                                          y: (strip.bounds.height - button.frame.height) / 2))
            strip.addSubview(button)
            let window = NSWindow(contentRect: strip.frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance.name)
            window.contentView = strip
            window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            window.orderFront(nil)
            settle(turns: 10)
            capture(strip, to: out.appendingPathComponent("menubar-\(name)-\(appearance.rawValue).png"))
            window.orderOut(nil)
        }
    }

    // MARK: - Popover

    private static func renderPopover(model: AppModel, fixture: Snapshot,
                                      registration: AgentRegistrationModel,
                                      appearance: Appearance, into out: URL) {
        // Capture the whole shared chrome on every tab, not detached tab bodies.
        for section in FleetSection.allCases {
            model.requestedSection = section
            let name = section.menuTitle.lowercased().replacingOccurrences(of: " ", with: "-")
            renderPopoverSurface(AnyView(FleetPopover(model: model, openDashboard: {}, registration: registration)),
                                 named: "popover-" + name, model: model, fixture: fixture,
                                 appearance: appearance, into: out)
        }
        // The administration rows on their own. Inside the Connections tab they
        // sit below a scroll fold that a still capture cannot reach, and a
        // surface the sheet cannot show is a surface nobody reviews.
        renderPopoverSurface(AnyView(NetworkAdminPreview(model: model)),
                             named: "popover-network-admin", model: model, fixture: fixture,
                             appearance: appearance, into: out)
        // The diagnostic panel carrying output far taller than its 132pt bound.
        // It shipped for a release drawing straight over the rows beneath it, and
        // no surface caught that because no fixture ever put enough text in it.
        // A four-line ping never reaches the bound; a support bundle is hundreds.
        model.actions.previewOutcome(title: "Copied support bundle",
                                     output: Self.tallDiagnosticFixture)
        renderPopoverSurface(AnyView(NetworkAdminPreview(model: model)),
                             named: "popover-network-admin-output", model: model,
                             fixture: fixture, appearance: appearance, into: out)
        model.actions.clearOutcome()

        renderPopoverSurface(AnyView(OverlaysPreview(model: model)),
                             named: "popover-overlays", model: model, fixture: fixture,
                             appearance: appearance, into: out)
        renderPopoverSurface(AnyView(ConnectionsPopover(model: model, openDashboard: {},
                                                        embedded: false)),
                             named: "standalone-network", model: model, fixture: fixture,
                             appearance: appearance, into: out)
    }

    /// Deliberately far taller than the panel's bound — the whole point of the
    /// surface is to prove the overflow is clipped and scrolled, not painted.
    private static let tallDiagnosticFixture: String = {
        let interfaces = ["en0", "en5", "en6", "en7", "utun4"]
        return interfaces.map { name in
            """
            {
              "bsdName" : "\(name)",
              "displayName" : "Ethernet Adapter (\(name))",
              "hasLink" : false,
              "ipv4" : [ ],
              "ipv6" : [ ],
              "isUp" : true,
              "kind" : "ethernet",
              "macAddress" : "<mac>",
              "mtu" : 1500
            }
            """
        }.joined(separator: ",\n")
    }()

    private static func renderPopoverSurface(_ view: AnyView, named name: String,
                                             model: AppModel, fixture: Snapshot,
                                             appearance: Appearance, into out: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: appearance.name)
        hosting.frame = NSRect(x: 0, y: 0, width: popoverWidth, height: 700)

        // A hosting view has to be in a window before SwiftUI will lay it out
        // against a real appearance and give a usable `fittingSize`.
        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance.name)
        // The real popover draws on `NSPopover`'s own backdrop, so this content
        // is transparent by itself. Without a fill behind it the dark capture
        // came out as white-on-white — every label invisible, which reads as a
        // broken surface rather than a missing backdrop.
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)

        hold(model, fixture)
        let fitted = hosting.fittingSize
        window.setContentSize(NSSize(width: popoverWidth, height: fitted.height))
        hold(model, fixture)

        // The window, not the hosting view — same as the console path. A view
        // captured on its own carries no window backdrop.
        capture(window, to: out.appendingPathComponent("\(name)-\(appearance.rawValue).png"))
        window.orderOut(nil)
    }

    // MARK: - Console

    private static func renderConsole(model: AppModel, fixture: Snapshot,
                                      appearance: Appearance, into out: URL) {
        let controller = ConsoleWindowController(model: model)
        controller.show()
        guard let window = controller.window else { return }

        // Park it where it cannot be seen. `cacheDisplay` needs the window
        // ordered in — it renders the view's backing store, not the screen — so
        // it cannot simply be left unordered.
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.appearance = NSAppearance(named: appearance.name)
        hold(model, fixture)

        for module in ConsoleModule.allCases {
            mutate {
                controller.console.atHome = false
                controller.console.module = module
                controller.console.reconcileSelection(model: model)
            }
            hold(model, fixture)
            capture(window, to: out.appendingPathComponent(
                "console-\(module.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))-\(appearance.rawValue).png"))
        }
        // The narrow layout is a separate acceptance surface for every module.
        window.setContentSize(NSSize(width: 982, height: 720))
        for module in ConsoleModule.allCases {
            mutate { controller.console.open(module) }
            hold(model, fixture)
            capture(window, to: out.appendingPathComponent(
                "compact-\(module.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))-\(appearance.rawValue).png"))
        }
        window.setContentSize(DashboardWindowGeometry.defaultContentSize)

        // Home — the priority view the window opens on.
        mutate { controller.console.goHome() }
        hold(model, fixture)
        capture(window, to: out.appendingPathComponent("console-home-\(appearance.rawValue).png"))

        // Inspectors, each driven by the selection that produces it.
        mutate { controller.console.atHome = false }
        let inspectors: [(String, () -> Void)] = [
            ("service", {
                controller.console.open(.services)
                controller.console.selectedServiceID = Fixtures.healthyServiceID
            }),
            ("service-crashed", {
                controller.console.module = .services
                controller.console.selectedServiceID = Fixtures.crashedServiceID
            }),
            ("unmanaged", {
                controller.console.module = .services
                controller.console.selectedServiceID = nil
                controller.console.selectedUnmanagedID = Fixtures.unmanagedID
            }),
            ("device", {
                controller.console.module = .overview
                controller.console.selectedDeviceID = Fixtures.peerDeviceID
            }),
        ]
        for (name, apply) in inspectors {
            mutate(apply)
            hold(model, fixture)
            capture(window, to: out.appendingPathComponent(
                "inspector-\(name)-\(appearance.rawValue).png"))
        }
        mutate { controller.console.selectedDeviceID = "self" }

        // The chrome tool panels.
        //
        // Terminal and Files come out with their header, close button and panel
        // frame drawn and the emulator body **blank**. `cacheDisplay` walks the
        // AppKit drawing path, and SwiftTerm renders the grid through its own
        // Metal layer, which that path cannot see — the same reason the package
        // compiles a .metal shader at build time.
        //
        // Capturing the emulator would mean CGWindowListCreateImage, which needs
        // Screen Recording consent and would put a permission prompt in the
        // middle of a build script. A blank body that is visibly blank is a
        // better outcome than a screenshot tool that silently starts asking for
        // recording rights, so the limitation stays and is stated here.
        for tool in ConsoleTool.allCases {
            mutate { controller.tools.toggle(tool, context: ToolContext()) }
            hold(model, fixture, turns: 20)
            capture(window, to: out.appendingPathComponent(
                "chrome-\(tool.rawValue.lowercased())-\(appearance.rawValue).png"))
            mutate { controller.tools.dismiss() }
            hold(model, fixture)
        }

        window.orderOut(nil)
    }

    // MARK: - Capture

    /// SwiftUI lays out on the run loop, and an `@Observable` write does not
    /// take effect until it has turned. One turn is enough for a module switch;
    /// a tool panel spawning a process needs more.
    private static func settle(turns: Int = 6) {
        let deadline = Date().addingTimeInterval(Double(turns) * 0.02)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: deadline)
        }
    }

    private static func capture(_ window: NSWindow, to url: URL) {
        // The frame view, not the content view — the titlebar, its accessory
        // pill and the toolbar are part of the surface being documented.
        guard let frameView = window.contentView?.superview else { return }
        capture(frameView, to: url)
    }

    private static func capture(_ view: NSView, to url: URL) {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        rep.size = bounds.size
        // `bitmapImageRepForCachingDisplay` can hand back a rep the view is
        // already using, and `cacheDisplay` only repaints what is dirty — so
        // without marking the whole frame dirty first, a capture can carry
        // pixels from the previous surface.
        view.setNeedsDisplay(bounds)
        view.window?.displayIfNeeded()
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
        print("  \(url.lastPathComponent)")
    }
}

// MARK: - Fixtures

@MainActor
enum Fixtures {
    // Stable display-only identity. These paths are never opened by the fixture.
    static let userName = "demo"
    static let homePath = "/Users/demo"
    // Demo process identities are injected before any collector/timer starts.
    // Live verification does not use this branch or these measurements.
    static let processRows: [ProcessRow] = [
        (Int32(48122), "Demo API", "python3 -m http.server 8787", 4.2, Int64(186_000_000), [8787]),
        (Int32(51903), "Demo Web", "npm run dev", 11.8, Int64(412_000_000), [5173]),
        (Int32(52004), "Demo Indexer", "python3 indexer.py", 2.5, Int64(240_000_000), []),
        (Int32(52005), "Demo Agent", "codex", 1.1, Int64(120_000_000), [])
    ].map { pid, name, command, cpu, memory, ports in
        ProcessRow(id: pid, pid: pid, ppid: 1, pgid: pid, uid: 501, user: userName,
                   name: name, commandLine: command, cpuPercent: cpu, residentBytes: memory,
                   ports: ports, startSignature: "demo-\(pid)", stateField: "S")
    }
    private static let serviceLogsPath = "\(homePath)/Library/Logs/FleetConsole/services"
    private static let socketPath = "\(homePath)/Library/Application Support/FleetConsole/fleetd.sock"

    /// Synthetic config declarations using RFC 5737 documentation subnets.
    /// They need not match the rendering machine's live interfaces.
    static let segments: [FleetConfig.SegmentConfig] = [
        .init(tag: 40, name: "Demo Guest", cidr: "192.0.2.0/24", gateway: "192.0.2.1",
              purpose: "isolated wireless"),
        .init(name: "Demo LAN", cidr: "198.51.100.0/24", gateway: "198.51.100.1",
              purpose: "trusted wired"),
    ]

    static let healthyServiceID = "svc-api"
    static let crashedServiceID = "svc-indexer"
    static let unmanagedID = "44460:a1b2"
    static let peerDeviceID = "peer"

    private static func ago(_ seconds: TimeInterval) -> Date {
        Date().addingTimeInterval(-seconds)
    }

    static func snapshot() -> Snapshot {
        Snapshot(
            generatedAt: Date(),
            daemon: DaemonInfo(version: "1.0.0", pid: 14066, startedAt: ago(9_240),
                               lastTickAt: ago(2), lastReconcileAt: ago(31),
                               tickIntervalSec: 5,
                               socketPath: socketPath),
            services: services(),
            unmanaged: unmanaged(),
            devices: devices(),
            attention: attention(),
            recentEvents: events())
    }

    // MARK: Services — one per status tone, so the sheet carries the whole
    // vocabulary rather than five rows of green.

    private static func services() -> [ServiceRecord] {
        [
            // Healthy: a check ran and passed. The only state that earns green.
            ServiceRecord(
                id: healthyServiceID, friendlyName: "api", ownerAgent: "claude",
                purpose: "local API for triage",
                command: ["python3", "-m", "local.api"],
                cwd: "\(homePath)/Workspace/api",
                pid: 48122, pgid: 48122, startSignature: "1a2b3c",
                declaredPorts: [8787], startedAt: ago(7_400),
                leaseExpiresAt: Date().addingTimeInterval(4_180), leaseTTLSec: 7_200,
                lastRenewedAt: ago(3_020),
                health: HealthSpec(kind: .http, target: "http://127.0.0.1:8787/healthz"),
                state: .healthy,
                evidence: Evidence(processExists: true, listeningPorts: [8787],
                                   portScanRan: true, healthCheckRan: true,
                                   healthPassed: true, healthDetail: "200 in 12 ms",
                                   healthLatencyMs: 12, checkedAt: ago(3)),
                resources: ResourceSample(cpuPct: 4.2, memMB: 186, processCount: 1,
                                          sampledAt: ago(3)),
                stdoutPath: "\(serviceLogsPath)/api.out",
                stderrPath: "\(serviceLogsPath)/api.err"),

            // Running (unverified): alive, listening, but no check configured —
            // the best state a service without a health check can reach.
            ServiceRecord(
                id: "svc-web", friendlyName: "web", ownerAgent: "claude",
                purpose: "vite dev server for the console UI",
                command: ["npm", "run", "dev"],
                cwd: "\(homePath)/Workspace/fleet-web",
                pid: 51903, pgid: 51903, startSignature: "4d5e6f",
                declaredPorts: [5173], startedAt: ago(2_150),
                leaseExpiresAt: Date().addingTimeInterval(1_450), leaseTTLSec: 3_600,
                state: .running,
                evidence: Evidence(processExists: true, listeningPorts: [5173],
                                   portScanRan: true, checkedAt: ago(3)),
                resources: ResourceSample(cpuPct: 11.8, memMB: 412, processCount: 3,
                                          sampledAt: ago(3))),

            // Degraded: passing its check, breaching a budget.
            ServiceRecord(
                id: "svc-embed", friendlyName: "embed", ownerAgent: "local",
                purpose: "embedding worker for local search",
                command: ["python3", "-m", "embed.worker", "--batch", "64"],
                cwd: "\(homePath)/Workspace/embed",
                pid: 52741, pgid: 52741, startSignature: "7g8h9i",
                declaredPorts: [], startedAt: ago(5_600),
                leaseExpiresAt: Date().addingTimeInterval(2_400), leaseTTLSec: 7_200,
                budget: ResourceBudget(maxRuntimeSec: 14_400, cpuWarnPct: 60),
                health: HealthSpec(kind: .tcp, target: "127.0.0.1:9931"),
                state: .degraded,
                evidence: Evidence(processExists: true, listeningPorts: [9931],
                                   portScanRan: true, healthCheckRan: true,
                                   healthPassed: true, healthDetail: "connected in 3 ms",
                                   healthLatencyMs: 3, checkedAt: ago(4)),
                resources: ResourceSample(cpuPct: 88.4, memMB: 2_140, processCount: 2,
                                          sampledAt: ago(4)),
                budgetBreaches: ["cpu 88% over 60% warn threshold"]),

            // Expiring: the lease is nearly up and nobody has renewed it.
            ServiceRecord(
                id: "svc-tunnel", friendlyName: "tunnel", ownerAgent: "codex",
                purpose: "ssh tunnel to the staging box",
                command: ["ssh", "-N", "-L", "6432:localhost:5432", "staging"],
                cwd: homePath,
                pid: 53880, pgid: 53880, startSignature: "j1k2l3",
                declaredPorts: [6432], startedAt: ago(1_780),
                leaseExpiresAt: Date().addingTimeInterval(94), leaseTTLSec: 1_800,
                state: .expiring,
                evidence: Evidence(processExists: true, listeningPorts: [6432],
                                   portScanRan: true, checkedAt: ago(5)),
                resources: ResourceSample(cpuPct: 0.1, memMB: 9, processCount: 1,
                                          sampledAt: ago(5))),

            // Unhealthy: the check ran and failed, repeatedly.
            ServiceRecord(
                id: "svc-search", friendlyName: "search", ownerAgent: "claude",
                purpose: "meilisearch index for notes",
                command: ["meilisearch", "--db-path", ".meili"],
                cwd: "\(homePath)/Workspace/notes",
                pid: 54219, pgid: 54219, startSignature: "m4n5o6",
                declaredPorts: [7700], startedAt: ago(880),
                leaseExpiresAt: Date().addingTimeInterval(2_700), leaseTTLSec: 3_600,
                health: HealthSpec(kind: .http, target: "http://127.0.0.1:7700/health"),
                state: .unhealthy,
                evidence: Evidence(processExists: true, listeningPorts: [],
                                   portScanRan: true, healthCheckRan: true,
                                   healthPassed: false,
                                   healthDetail: "connection refused",
                                   checkedAt: ago(4)),
                resources: ResourceSample(cpuPct: 0.0, memMB: 64, processCount: 1,
                                          sampledAt: ago(4)),
                consecutiveHealthFailures: 6),

            // Crashed: exited without being asked to. Terminal, so it drops out
            // of `activeServices` and only shows where history is shown.
            ServiceRecord(
                id: crashedServiceID, friendlyName: "indexer", ownerAgent: "local",
                purpose: "nightly re-index of the workspace",
                command: ["cargo", "run", "--release", "--bin", "indexer"],
                cwd: "\(homePath)/Workspace/indexer",
                pid: nil, startSignature: "p7q8r9",
                declaredPorts: [], startedAt: ago(12_400),
                leaseExpiresAt: ago(600), leaseTTLSec: 7_200,
                state: .crashed,
                evidence: Evidence(processExists: false, portScanRan: true,
                                   checkedAt: ago(600)),
                restartCount: 2, lastExitCode: 101),

            // Claimed, expired, three ports. The case the row layout actually
            // fails on: every accessory in a row is `fixedSize`, so "Claimed" +
            // "Expired" + a three-port list claimed the whole width and the row
            // took it out of the only compressible thing left — the title. The
            // real fleet had one of these and 42 surfaces had none, so the sheet
            // showed rows with names while the app showed one without.
            ServiceRecord(
                id: "svc-claimed", friendlyName: "llama-server", ownerAgent: "operator",
                purpose: "claimed from the unmanaged list",
                command: ["llama-server", "--port", "8080"],
                cwd: "\(homePath)/Workspace/models",
                pid: 92416, pgid: 92416, startSignature: "s1t2u3",
                declaredPorts: [8080, 8081, 8082], startedAt: ago(93_600),
                leaseExpiresAt: ago(70_200), leaseTTLSec: 7_200,
                state: .expired,
                evidence: Evidence(processExists: true, listeningPorts: [8080, 8081, 8082],
                                   portScanRan: true, checkedAt: ago(6)),
                resources: ResourceSample(cpuPct: 0.4, memMB: 5_120, processCount: 1,
                                          sampledAt: ago(6))),
        ]
        .map { record -> ServiceRecord in
            guard record.id == "svc-claimed" else { return record }
            var claimed = record
            claimed.claimed = true
            claimed.claimedAt = ago(93_000)
            return claimed
        }
    }

    private static func unmanaged() -> [UnmanagedProcess] {
        [
            UnmanagedProcess(
                id: unmanagedID, pid: 44460, command: "Python",
                commandLine: "python3 -m http.server 8765 --directory \(homePath)/Workspace/scratch",
                user: userName, ports: [8765],
                firstSeen: ago(66_000), lastSeen: ago(4),
                reason: .listenerNotInRegistry),
            UnmanagedProcess(
                id: "93129:s1t2", pid: 93129, command: "platform-server",
                commandLine: "target/debug/platform-server --port 8788",
                user: userName, ports: [8788],
                firstSeen: ago(41_000), lastSeen: ago(4),
                reason: .devServerShape),
            UnmanagedProcess(
                id: "83029:u3v4", pid: 83029, command: "node",
                commandLine: "node \(homePath)/Workspace/old-app/node_modules/.bin/vite --port 5174",
                user: userName, ports: [5174],
                firstSeen: ago(9_800), lastSeen: ago(4),
                reason: .escapedProcessGroup,
                formerServiceID: "svc-old-web"),
        ]
    }

    private static func devices() -> [DeviceRecord] {
        var this = DeviceRecord(id: "self", name: "Demo Mac",
                                model: "Mac", localHost: "127.0.0.1")
        this.evidence = DeviceEvidence(icmpOK: true, icmpRTTms: 0.1, tcpOK: true)
        this.lastReachableAt = ago(2)

        var peer = DeviceRecord(id: peerDeviceID, name: "demo-studio", model: "Mac Studio",
                                localHost: "studio.example.invalid", tailscaleHost: "studio.tail.example.invalid",
                                tailscaleIP: "203.0.113.42", localIP: "198.51.100.42",
                                probePort: 22)
        peer.evidence = DeviceEvidence(icmpOK: true, icmpRTTms: 3.8, tcpOK: true)
        peer.lastReachableAt = ago(6)
        peer.metrics = HostMetrics(cpuPct: 22.5, memUsedGB: 18.2, memTotalGB: 64)

        var offline = DeviceRecord(id: "laptop", name: "demo-air", model: "MacBook Air",
                                   localHost: "air.example.invalid", tailscaleHost: "air.tail.example.invalid",
                                   probePort: 22)
        offline.evidence = DeviceEvidence(icmpOK: false, tcpOK: false)
        offline.lastReachableAt = ago(28_800)
        offline.remoteError = "no route to host"

        return [this, peer, offline]
    }

    private static func attention() -> [AttentionItem] {
        [
            AttentionItem(id: "att-search", severity: .critical,
                          title: "search has failed its health check 6 times",
                          detail: "http://127.0.0.1:7700/health — connection refused",
                          serviceID: "svc-search", since: ago(760)),
            AttentionItem(id: "att-tunnel", severity: .warning,
                          title: "tunnel's lease expires in under 2 minutes",
                          detail: "codex has not renewed it since it was launched",
                          serviceID: "svc-tunnel", since: ago(120)),
            AttentionItem(id: "att-unmanaged", severity: .warning,
                          title: "Python is listening on 8765 with no registry record",
                          detail: "Started outside the controller — visibility only, "
                                + "no stop available",
                          unmanagedID: unmanagedID, since: ago(66_000)),
        ]
    }

    /// Newest first, and monotonic — which is what the daemon delivers.
    ///
    /// `registry.events` is `ORDER BY seq DESC` and the module does not re-sort, so
    /// the header's "newest first" is a claim the daemon backs and the view passes
    /// through. This fixture used to be in neither order, which rendered a scrambled
    /// log on the one surface anybody reviews the Event Log from — a sheet that
    /// disagrees with the app teaches reviewers to stop trusting the sheet.
    private static func events() -> [ServiceEvent] {
        // Descending age, so `seq` and `ts` agree the way an append-only log's do.
        var seq: Int64 = 4_108
        func next() -> Int64 { seq -= 1; return seq + 1 }
        return [
            ServiceEvent(seq: next(), serviceID: "svc-tunnel", serviceName: "tunnel",
                         ts: ago(120), kind: .leaseExpiring, detail: "94s remaining"),
            ServiceEvent(seq: next(), serviceID: "svc-embed", serviceName: "embed",
                         ts: ago(420), kind: .budgetWarning,
                         detail: "cpu 88% over 60% warn threshold"),
            ServiceEvent(seq: next(), serviceID: crashedServiceID, serviceName: "indexer",
                         ts: ago(600), kind: .restarted, detail: "exit 101 — restart 2 of 3"),
            ServiceEvent(seq: next(), serviceID: "svc-search", serviceName: "search",
                         ts: ago(760), kind: .healthFailed,
                         detail: "connection refused (6 consecutive)"),
            ServiceEvent(seq: next(), serviceID: healthyServiceID, serviceName: "api",
                         ts: ago(3_020), kind: .leaseRenewed, detail: "+2h by claude"),
            ServiceEvent(seq: next(), serviceID: healthyServiceID, serviceName: "api",
                         ts: ago(7_380), kind: .healthPassed, detail: "200 in 12 ms"),
            ServiceEvent(seq: next(), serviceID: healthyServiceID, serviceName: "api",
                         ts: ago(7_398), kind: .started, detail: "pid 48122, port 8787"),
            ServiceEvent(seq: next(), serviceID: healthyServiceID, serviceName: "api",
                         ts: ago(7_400), kind: .registered,
                         detail: "claude — local API for triage"),
        ]
    }
}
#endif
