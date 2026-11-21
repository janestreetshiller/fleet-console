#if FLEET_SURFACE_RENDERER
import AppKit
import SwiftUI
import FleetCore

@MainActor
enum SurfaceRenderer {
    nonisolated static let flag = "--render-surfaces"
    nonisolated static let overviewOnlyFlag = "--render-surfaces-only"

    private static let popoverWidth: CGFloat = FleetMetrics.popoverWidth

    static let churnFlag = "--measure-churn"

    static func runIfRequested() -> Bool {
        let overviewOnly = CommandLine.arguments.contains(overviewOnlyFlag)
        if overviewOnly && (!CommandLine.arguments.contains(flag)
            || CommandLine.arguments.contains(churnFlag)
            || CommandLine.arguments.contains("--verify-live")) {
            fputs("--render-surfaces-only requires --render-surfaces <directory> and cannot run live verification or probes.\n", stderr)
            exit(2)
        }
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

        if overviewOnly {
            let fixtureHome = out.appendingPathComponent("fixture-home").standardizedFileURL.path
            guard ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] == fixtureHome,
                  FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path == fixtureHome else {
                fputs("Bounded capture requires CFFIXED_USER_HOME=<output-directory>/fixture-home.\n", stderr)
                exit(2)
            }
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()

        render(into: out, overviewOnly: overviewOnly)
        return true
    }

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

    private static func render(into out: URL, overviewOnly: Bool = false) {
        let model = overviewOnly
            ? AppModel(billing: OurosBilling(useKeychain: false))
            : AppModel()
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
        let rosterFile = out.appendingPathComponent(".fixture-agents-\(UUID().uuidString).json")
        do {
            try JSONEncoder().encode(["claude", "codex", "operator"])
                .write(to: rosterFile, options: .withoutOverwriting)
        } catch { fatalError("Cannot create isolated fixture roster: \(error)") }
        defer { try? FileManager.default.removeItem(at: rosterFile) }
        let registration = AgentRegistrationModel(fileURL: rosterFile)

        VLANRegistry.shared.adopt(Fixtures.segments)

        for appearance in (overviewOnly ? [Appearance.dark] : Appearance.allCases) {
            NSApp.appearance = NSAppearance(named: appearance.name)
            if overviewOnly {
                model.requestedSection = .quickView
                renderPopoverSurface(AnyView(FleetPopover(model: model, openDashboard: {}, registration: registration)),
                                     named: "popover-quick-view", model: model, fixture: fixture,
                                     appearance: appearance, into: out)
                let controller = ConsoleWindowController(model: model)
                controller.console.atHome = false
                controller.console.module = .overview
                controller.show(activate: false)
                guard let window = controller.window else { fatalError("No fixture overview window") }
                window.appearance = NSAppearance(named: appearance.name)
                hold(model, fixture)
                capture(window, to: out.appendingPathComponent("console-overview-\(appearance.rawValue).png"))
                window.orderOut(nil)
                continue
            }
            renderMenuBar(model: model, appearance: appearance, into: out)
            renderPopover(model: model, fixture: fixture, registration: registration, appearance: appearance, into: out)
            renderConsole(model: model, fixture: fixture, appearance: appearance, into: out)
            let agentConsole = ConsoleModel()
            agentConsole.openOperationsSection("Agents")
            for width in [560.0, 900.0] {
                hold(model, Fixtures.snapshot(), turns: 2)
                renderStandalone(AnyView(AgentTopologyWorkspace(model: model, console: agentConsole)
                    .frame(width: width, height: 820)), name: "agent-map-\(Int(width))",
                    size: NSSize(width: width, height: 820), appearance: appearance, into: out)
            }
            model.connected = false
            renderStandalone(AnyView(AgentTopologyWorkspace(model: model, console: agentConsole)
                .frame(width: 900, height: 820)), name: "agent-map-offline",
                size: NSSize(width: 900, height: 820), appearance: appearance, into: out)
            hold(model, fixture)

            renderTaskComposer(registration: registration, appearance: appearance, into: out)
            renderStandalone(AnyView(DeviceManagementView(model: model)), name: "device-management",
                             size: NSSize(width: 600, height: 650), appearance: appearance, into: out)
            renderStandalone(AnyView(OurosAgentSheet(model: model)), name: "ouros-agent",
                             size: NSSize(width: 620, height: 440), appearance: appearance, into: out)
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

    private static func mutate(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }

    private static func hold(_ model: AppModel, _ fixture: Snapshot, turns: Int = 30) {
        settle(turns: max(turns, 30))
        mutate { model.apply(fixture) }
        model.connected = true
        model.connectionError = nil
        model.lastSnapshotAt = fixture.generatedAt
        settle(turns: 3)
    }

    enum Appearance: String, CaseIterable {
        case light, dark
        var name: NSAppearance.Name { self == .light ? .aqua : .darkAqua }
    }

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

    private static func renderPopover(model: AppModel, fixture: Snapshot,
                                      registration: AgentRegistrationModel,
                                      appearance: Appearance, into out: URL) {
        for section in FleetSection.allCases {
            model.requestedSection = section
            let name = section.menuTitle.lowercased().replacingOccurrences(of: " ", with: "-")
            renderPopoverSurface(AnyView(FleetPopover(model: model, openDashboard: {}, registration: registration)),
                                 named: "popover-" + name, model: model, fixture: fixture,
                                 appearance: appearance, into: out)
        }
        renderPopoverSurface(AnyView(NetworkAdminPreview(model: model)),
                             named: "popover-network-admin", model: model, fixture: fixture,
                             appearance: appearance, into: out)
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

        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance.name)
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)

        hold(model, fixture)
        let fitted = hosting.fittingSize
        window.setContentSize(NSSize(width: popoverWidth, height: fitted.height))
        hold(model, fixture)

        capture(window, to: out.appendingPathComponent("\(name)-\(appearance.rawValue).png"))
        window.orderOut(nil)
    }

    private static func renderConsole(model: AppModel, fixture: Snapshot,
                                      appearance: Appearance, into out: URL) {
        let controller = ConsoleWindowController(model: model)
        controller.show()
        guard let window = controller.window else { return }

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
        mutate { controller.console.openOperationsSection("Agents") }
        hold(model, fixture)
        capture(window, to: out.appendingPathComponent("console-agent-topology-\(appearance.rawValue).png"))
        window.setContentSize(NSSize(width: 982, height: 720))
        hold(model, fixture)
        capture(window, to: out.appendingPathComponent("compact-agent-topology-\(appearance.rawValue).png"))
        mutate { controller.console.openOperationsSection("Services") }
        window.setContentSize(NSSize(width: 982, height: 720))
        for module in ConsoleModule.allCases {
            mutate { controller.console.open(module) }
            hold(model, fixture)
            capture(window, to: out.appendingPathComponent(
                "compact-\(module.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))-\(appearance.rawValue).png"))
        }
        window.setContentSize(DashboardWindowGeometry.defaultContentSize)

        mutate { controller.console.goHome() }
        hold(model, fixture)
        capture(window, to: out.appendingPathComponent("console-home-\(appearance.rawValue).png"))

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

    private static func settle(turns: Int = 6) {
        let deadline = Date().addingTimeInterval(Double(turns) * 0.02)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: deadline)
        }
    }

    private static func capture(_ window: NSWindow, to url: URL) {
        guard let frameView = window.contentView?.superview else { return }
        capture(frameView, to: url)
    }

    private static func capture(_ view: NSView, to url: URL) {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        rep.size = bounds.size
        view.setNeedsDisplay(bounds)
        view.window?.displayIfNeeded()
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
        print("  \(url.lastPathComponent)")
    }
}

@MainActor
enum Fixtures {
    static let userName = "demo"
    static let homePath = "/Users/demo"
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

    private static func services() -> [ServiceRecord] {
        [
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

    private static func events() -> [ServiceEvent] {
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
