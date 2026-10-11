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
            fputs("Usage: --verify-live <output-directory> [seconds] [--verify-daemon-socket <path>]\n", stderr)
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
        let hasDuration = index + 2 < arguments.count
            && arguments[index + 2] != "--verify-daemon-socket"
        let seconds = hasDuration ? Double(arguments[index + 2]) ?? .nan : 20
        guard seconds.isFinite, seconds >= 10, seconds <= 3_600 else {
            fputs("Verification duration must be between 10 and 3600 seconds.\n", stderr)
            exit(2)
        }
        let output = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { fputs("Cannot create verification directory: \(error)\n", stderr); exit(1) }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
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

    private static func spin(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.current.run(mode: .default, before: min(end, Date().addingTimeInterval(0.05)))
        }
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
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
