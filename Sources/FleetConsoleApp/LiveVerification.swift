#if FLEET_SURFACE_RENDERER
import AppKit
import SwiftUI
import FleetCore
import Darwin

/// Runs the actual window, probes and navigation with no fixture injection,
/// helper registration, notification prompts or foreground activation.
@MainActor
enum LiveVerification {
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--verify-live") else {
            return false
        }
        guard index + 1 < arguments.count else {
            fputs("Usage: --verify-live <output-directory> [seconds:10...3600] [--verify-quick-view] [--verify-daemon-socket <path>]\n", stderr)
            exit(2)
        }
        if let socketIndex = arguments.firstIndex(of: "--verify-daemon-socket") {
            guard socketIndex + 1 < arguments.count,
                  !arguments[socketIndex + 1].isEmpty,
                  !arguments[socketIndex + 1].hasPrefix("--") else {
                fputs("--verify-daemon-socket requires a socket path.\n", stderr)
                exit(2)
            }
        }
        guard let seconds = LiveVerificationArguments.duration(arguments) else {
            fputs("Usage: --verify-live <output-directory> [seconds:10...3600] [--verify-quick-view] [--verify-daemon-socket <path>]\n", stderr)
            exit(2)
        }
        let output = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { fputs("Cannot create verification directory: \(error)\n", stderr); exit(1) }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        if arguments.contains("--verify-quick-view") {
            return verifyQuickView(output: output, seconds: seconds)
        }
        let model = AppModel()
        let controller = ConsoleWindowController(model: model)
        let initialOverviewPassed = !controller.console.atHome && controller.console.module == .overview
        let initialInspectorPassed = !controller.console.inspectorRevealed
        controller.console.atHome = false
        controller.console.module = .overview
        controller.show(activate: false)
        guard let window = controller.window else { fatalError("No native console window") }
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        spin(6)
        NotificationCenter.default.post(name: ConsoleCommand.focusSearch, object: nil)
        spin(0.2)
        let searchField = nativeSearchField(in: window.contentView?.superview)
        let toolbarSearchPassed = searchField != nil
        let searchFocusPassed = searchField.map { field in
            window.firstResponder === field || (field.currentEditor().map {
                window.firstResponder === $0
            } ?? false)
        } ?? false
        window.makeFirstResponder(nil)
        let startCPU = cpuSeconds()
        let start = ProcessInfo.processInfo.systemUptime
        spin(seconds)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let cpuPercent = (cpuSeconds() - startCPU) / elapsed * 100
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let sizes: [(String, NSSize)] = [
            ("compact", NSSize(width: 982, height: 720)),
            ("standard", NSSize(width: 1240, height: 820)),
            ("wide", NSSize(width: 1560, height: 900))
        ]
        var captures: [String] = []
        for (name, size) in sizes {
            for (appearance, value) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                NSApp.appearance = NSAppearance(named: value)
                window.appearance = NSAppearance(named: value)
                window.setContentSize(size)
                spin(0.4)
                let filename = "overview-\(name)-\(appearance).png"
                capture(window, to: output.appendingPathComponent(filename))
                captures.append(filename)
            }
        }
        NotificationCenter.default.post(name: ConsoleCommand.selectModule, object: nil,
                                        userInfo: [ConsoleCommand.userInfoModule: ConsoleModule.processes.rawValue])
        spin(0.3)
        let navigationPassed = controller.console.module == .processes && !controller.console.atHome
        controller.console.search = "FLEET_NO_MATCH_47C9"
        spin(0.3)
        capture(window, to: output.appendingPathComponent("processes-empty-dark.png"))
        captures.append("processes-empty-dark.png")
        NotificationCenter.default.post(name: ConsoleCommand.showHome, object: nil)
        spin(0.3)
        let homePassed = controller.console.atHome
        let network = model.system.network
        let power = model.system.power
        let networkHistorySamples = min(model.system.networkDownloadHistory.count,
                                        model.system.networkUploadHistory.count)
        let networkTelemetryPassed = TelemetryReadiness.network(
            probeSucceeded: network.probeSucceeded, hasActiveLink: !network.interfaceNames.isEmpty,
            download: network.downloadBytesPerSec, upload: network.uploadBytesPerSec,
            historySamples: networkHistorySamples
        )
        let powerTelemetryPassed = TelemetryReadiness.power(
            probeSucceeded: power.probeSucceeded, hasBattery: power.hasBattery,
            charge: power.chargeFraction
        )
        let daemonSnapshotAge = model.lastSnapshotReceivedUptime.map {
            ProcessInfo.processInfo.systemUptime - $0
        }
        let daemonSnapshotPassed = LiveDaemonReadiness.snapshot(
            connected: model.connected, hasDaemon: model.daemon != nil,
            ageSeconds: daemonSnapshotAge
        )
        let rpcOperations = DaemonClient.shared.submittedObservationalOperations
        let readOnlyPassed = DaemonClient.shared.requestPolicy == .observational
            && rpcOperations.allSatisfy { name in
                RPCOp(rawValue: name).map { RPCRequestPolicy.observational.allows($0) } == true
            }
        let valid = model.system.cpu.sampled && model.system.memory.totalBytes > 0
            && model.system.storage.totalBytes > 0 && !model.processes.rows.isEmpty
            && networkTelemetryPassed && powerTelemetryPassed && daemonSnapshotPassed && readOnlyPassed
        let passed = valid && navigationPassed && homePassed && initialOverviewPassed
            && initialInspectorPassed && toolbarSearchPassed && searchFocusPassed
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let receipt: [String: Any] = [
            "method": "native console window, live probes, no fixtures",
            "configuration": configuration,
            "valid": passed,
            "benchmarkSeconds": elapsed, "processCPUPercent": cpuPercent,
            "processPeakResidentBytes": usage.ru_maxrss,
            "cpuBrand": model.system.topology.brand,
            "logicalCores": model.system.topology.logicalCores,
            "cpuFraction": model.system.cpu.usage,
            "memoryUsedBytes": model.system.memory.usedBytes,
            "memoryTotalBytes": model.system.memory.totalBytes,
            "storageAvailableBytes": model.system.storage.availableBytes,
            "processCount": model.processes.rows.count,
            "cpuHistorySamples": model.system.cpuHistory.count,
            "daemonConnected": model.connected,
            "daemonSnapshotReceived": model.lastSnapshotReceivedUptime != nil,
            "daemonSnapshotAgeSeconds": daemonSnapshotAge as Any? ?? NSNull(),
            "daemonSnapshotPassed": daemonSnapshotPassed,
            "daemonPID": model.daemon?.pid as Any? ?? NSNull(),
            "daemonSocketPath": DaemonClient.shared.socketPath,
            "daemonConnectionError": model.connectionError as Any? ?? NSNull(),
            "networkProbeSucceeded": network.probeSucceeded,
            "activePhysicalInterfaces": network.interfaceNames.count,
            "networkTelemetryPassed": networkTelemetryPassed,
            "networkHistorySamples": networkHistorySamples,
            "downloadBytesPerSecond": network.downloadBytesPerSec as Any? ?? NSNull(),
            "uploadBytesPerSecond": network.uploadBytesPerSec as Any? ?? NSNull(),
            "powerProbeSucceeded": power.probeSucceeded,
            "powerTelemetryPassed": powerTelemetryPassed,
            "hasBattery": power.hasBattery,
            "batteryChargeFraction": power.chargeFraction as Any? ?? NSNull(),
            "readOnlyPassed": readOnlyPassed, "rpcOperations": rpcOperations,
            "initialOverviewPassed": initialOverviewPassed,
            "initialInspectorPassed": initialInspectorPassed,
            "toolbarSearchPassed": toolbarSearchPassed, "searchFocusPassed": searchFocusPassed,
            "navigationPassed": navigationPassed, "homePassed": homePassed,
            "captures": captures
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("receipt.json"))
            print(String(decoding: data, as: UTF8.self))
        } catch { fputs("Verification receipt failed: \(error)\n", stderr); exit(1) }
        window.orderOut(nil)
        DaemonClient.shared.stop()
        guard passed else { exit(1) }
        return true
    }

    private static func verifyQuickView(output: URL, seconds: Double) -> Bool {
        let model = AppModel()
        let controller = ConsoleWindowController(model: model)
        let openDashboard: () -> Void = {
            controller.show(activate: false)
            if CommandLine.arguments.contains("--review-ui") { controller.window?.center() }
        }
        let hosting = NSHostingView(rootView: FleetPopover(model: model, openDashboard: openDashboard))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: FleetMetrics.popoverWidth, height: 320),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.backgroundColor = .windowBackgroundColor
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)
        spin(6)
        window.setContentSize(NSSize(width: FleetMetrics.popoverWidth, height: max(250, hosting.fittingSize.height)))
        spin(0.2)
        let startCPU = cpuSeconds()
        let startChildrenCPU = cpuSeconds(RUSAGE_CHILDREN)
        let start = ProcessInfo.processInfo.systemUptime
        let initialSnapshotAt = model.lastSnapshotAt
        spin(seconds)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let processCPU = (cpuSeconds() - startCPU) / elapsed * 100
        let childrenCPU = (cpuSeconds(RUSAGE_CHILDREN) - startChildrenCPU) / elapsed * 100
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let network = model.system.network
        let power = model.system.power
        let age = model.lastSnapshotReceivedUptime.map { ProcessInfo.processInfo.systemUptime - $0 }
        let readOnly = DaemonClient.shared.requestPolicy == .observational
            && DaemonClient.shared.submittedObservationalOperations.allSatisfy { name in
                RPCOp(rawValue: name).map { RPCRequestPolicy.observational.allows($0) } == true
            }
        let daemonPassed = LiveDaemonReadiness.snapshot(connected: model.connected, hasDaemon: model.daemon != nil, ageSeconds: age)
        let metrics = QuickViewMetrics(cpu: model.system.cpu, memory: model.system.memory, storage: model.system.storage)
        let telemetryPassed = metrics.cpu.value != nil && metrics.memory.value != nil && metrics.disk.value != nil && readOnly
            && !model.processes.rows.isEmpty
            && TelemetryReadiness.network(probeSucceeded: network.probeSucceeded,
                hasActiveLink: !network.interfaceNames.isEmpty, download: network.downloadBytesPerSec,
                upload: network.uploadBytesPerSec, historySamples: model.system.networkDownloadHistory.count)
            && TelemetryReadiness.power(probeSucceeded: power.probeSucceeded, hasBattery: power.hasBattery,
                                       charge: power.chargeFraction)
            && daemonPassed
        var captures: [String] = []
        var sizes: [[String: Any]] = []
        var bounded = true
        for section in FleetSection.allCases {
            model.requestedSection = section
            let name = section.menuTitle.lowercased().replacingOccurrences(of: " ", with: "-")
            for (label, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                window.appearance = NSAppearance(named: appearance)
                spin(0.2)
                let size = hosting.fittingSize
                bounded = bounded && abs(size.width - FleetMetrics.popoverWidth) < 0.5
                    && size.height > DashboardContentGeometry.footerHeight
                    && size.height <= FleetMetrics.popoverBodyHeight + 100
                window.setContentSize(size)
                spin(0.1)
                let filename = "\(name)-\(label).png"
                capture(window, to: output.appendingPathComponent(filename))
                captures.append(filename)
                sizes.append(["section": section.menuTitle, "appearance": label,
                              "width": size.width, "height": size.height])
            }
        }
        // Capture the actual current inbox against this same live subscription,
        // never against fixture messages or a replacement daemon.
        let mailboxHosting = NSHostingView(rootView: AgentsMailboxSheet(model: model))
        let mailboxWindow = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 560, height: 520),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        mailboxWindow.contentView = mailboxHosting
        mailboxWindow.backgroundColor = .windowBackgroundColor
        mailboxWindow.orderFront(nil)
        for (label, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            mailboxWindow.appearance = NSAppearance(named: appearance)
            spin(0.3)
            let filename = "mailbox-current-\(label).png"
            capture(mailboxWindow, to: output.appendingPathComponent(filename))
            captures.append(filename)
        }
        mailboxWindow.orderOut(nil)
        let snapshotAdvanced = initialSnapshotAt.map { initial in
            model.lastSnapshotAt.map { $0 > initial } ?? false
        } ?? false
        let passed = telemetryPassed && bounded && snapshotAdvanced
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let receipt: [String: Any] = [
            "view": "quick-view", "method": "shipping SwiftUI popover in an offscreen native window, live probes",
            "configuration": configuration, "valid": passed, "benchmarkSeconds": elapsed,
            "processCPUPercent": processCPU, "collectorCPUPercent": childrenCPU,
            "appPlusCollectorsCPUPercent": processCPU + childrenCPU,
            "processPeakResidentBytes": usage.ru_maxrss,
            "cpuBrand": model.system.topology.brand, "logicalCores": model.system.topology.logicalCores,
            "readOnlyPassed": readOnly, "daemonSnapshotPassed": daemonPassed,
            "daemonPID": model.daemon?.pid as Any? ?? NSNull(),
            "initialSnapshotAt": initialSnapshotAt?.timeIntervalSince1970 as Any? ?? NSNull(),
            "finalSnapshotAt": model.lastSnapshotAt?.timeIntervalSince1970 as Any? ?? NSNull(),
            "snapshotAdvanced": snapshotAdvanced,
            "currentMessageCount": model.recentMessages.count,
            "historyMessageCount": model.messageHistory.count,
            "pendingReplyCount": model.awaitingReplyCount,
            "boundedPopoverPassed": bounded, "captureSizes": sizes, "captures": captures
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("receipt.json"))
            print(String(decoding: data, as: UTF8.self))
        } catch { fputs("Quick View receipt failed: \(error)\n", stderr); exit(1) }
        if passed && CommandLine.arguments.contains("--review-ui") {
            model.requestedSection = .quickView
            spin(0.2)
            NSApp.setActivationPolicy(.accessory)
            MainMenu.install { openDashboard() }
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.title = "FleetConsole UI Review"
            window.center()
            window.orderFront(nil)
            print("UI review pid \(ProcessInfo.processInfo.processIdentifier), window \(window.windowNumber)")
            fflush(stdout)
            NSApp.run()
        }
        window.orderOut(nil)
        DaemonClient.shared.stop()
        guard passed else { exit(1) }
        return true
    }

    private static func spin(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.current.run(mode: .default, before: min(end, Date().addingTimeInterval(0.05)))
        }
    }

    private static func cpuSeconds(_ who: Int32 = RUSAGE_SELF) -> Double {
        var usage = rusage()
        getrusage(who, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    private static func nativeSearchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let field = view as? NSSearchField { return field }
        for child in view.subviews {
            if let field = nativeSearchField(in: child) { return field }
        }
        return nil
    }

    private static func capture(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView?.superview,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fatalError("Native window has no backing store")
        }
        view.setNeedsDisplay(view.bounds)
        window.displayIfNeeded()
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("PNG encoding failed")
        }
        do { try data.write(to: url) }
        catch { fatalError("Capture failed: \(error)") }
    }
}
#endif
