import Foundation
import Testing
import FleetCore
@testable import FleetConsoleApp

@Suite(.serialized)
struct FixAgentTests {
    @Test("Queued fix requests in the same second retain distinct files and complete contents")
    func simultaneousRequestsKeepTheirContents() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = FixReport.location(now: now)
        let second = FixReport.location(now: now)
        #expect(first != second)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstPath = directory.appendingPathComponent(first.lastPathComponent)
        let secondPath = directory.appendingPathComponent(second.lastPathComponent)
        let firstRequest = FixReport.proposalPrompt(markdown: "First finding\n'quoted' café\n")
        let secondRequest = FixReport.proposalPrompt(markdown: "Second finding\nkeep both requests\n")
        try FixReport.write(firstRequest, to: firstPath)
        try FixReport.write(secondRequest, to: secondPath)
        #expect(try Data(contentsOf: firstPath) == Data(firstRequest.utf8))
        #expect(try Data(contentsOf: secondPath) == Data(secondRequest.utf8))
    }

    @MainActor @Test("The Fleet Agent handoff keeps the full request in a file and the terminal command short")
    func compactProposalHandoff() throws {
        let suite = "fix-agent-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("fleet-agent", forKey: "fleetconsole.fixAgent")
        let settings = FixAgentSettings(defaults: defaults) { _ in
            URL(fileURLWithPath: "/Fleet's App/bin/fleet-agent")
        }
        let capture = FixerLaunchCapture()
        let observer = NotificationCenter.default.addObserver(forName: ConsoleCommand.runInTerminal,
                                                              object: nil, queue: .main) { note in
            let command = note.userInfo?[ConsoleCommand.userInfoCommand] as? String ?? ""
            MainActor.assumeIsolated { capture.notifications.append(["command": command]) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        var saved: String?
        var path: URL?
        let item = AttentionItem(id: "readable", severity: .critical, title: "Worker failed",
                                 detail: "Full finding: \"worker's stderr\" — connection refused\n" + String(repeating: "long finding ", count: 100))
        let model = AppModel()
        model.sendToFixer([item], openDashboard: {}, settings: settings, loadReportEvents: { $0([]) },
                          writeReport: { request, location in saved = request; path = location })
        let command = try #require(capture.notifications.first?["command"])
        let request = try #require(saved)
        let location = try #require(path)
        #expect(command == "'/Fleet'\\''s App/bin/fleet-agent' propose --prompt-file " + location.path.shellQuoted)
        #expect(!command.contains("\n"))
        #expect(!command.contains(item.detail))
        #expect(request.hasPrefix("FleetConsole found the problems below on this Mac."))
        #expect(request.contains(item.detail))
        #expect(request.contains("Do not launch, restart, stop, renew or otherwise change any service."))
        if let evidence = ProcessInfo.processInfo.environment["FLEET_HANDOFF_EVIDENCE_DIR"] {
            let directory = URL(fileURLWithPath: evidence, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let before = "'/Fleet'\\''s App/bin/fleet-agent' propose " + request.shellQuoted
            let receipt: [String: Any] = [
                "entryPoint": "AppModel.sendToFixer -> ConsoleCommand.runInTerminal",
                "newCommand": command, "newCommandBytes": command.utf8.count,
                "previousInlineCommandBytesForSameRequest": before.utf8.count,
                "completeRequestBytes": request.utf8.count,
                "requestContainsCompleteFinding": request.contains(item.detail),
                "requestContainsReadOnlyPolicy": request.contains("Do not launch, restart, stop, renew or otherwise change any service."),
                "sample": "Test finding, not host diagnostics"
            ]
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("handoff-receipt.json"))
        }
    }

    @Test("A prompt survives the shell intact, quotes and all")
    func shellQuoting() {
        #expect("plain".shellQuoted == "'plain'")
        #expect("it's \"fine\" $HOME".shellQuoted == #"'it'\''s "fine" $HOME'"#)
    }

    @Test("Each fixer starts on the prompt the way its CLI expects")
    func commandLines() {
        #expect(FixAgentKind.claude.commandLine(prompt: "go") == "claude 'go'")
        #expect(FixAgentKind.codex.commandLine(prompt: "go") == "codex 'go'")
        #expect(FixAgentKind.fleetAgent.commandLine(prompt: "go") == "fleet-agent propose 'go'")
    }

    @MainActor @Test("A designation whose agent is gone falls back to an installed one")
    func designationFallsBack() throws {
        let suite = "fix-agent-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("codex", forKey: "fleetconsole.fixAgent")
        let settings = FixAgentSettings(defaults: defaults) { name in
            name == "claude" ? URL(fileURLWithPath: "/usr/local/bin/claude") : nil
        }
        #expect(settings.installed == [.claude])
        #expect(settings.designated == .claude)
        #expect(defaults.string(forKey: "fleetconsole.fixAgent") == "claude")

        let none = FixAgentSettings(defaults: defaults) { _ in nil }
        #expect(none.installed.isEmpty)
        #expect(none.designated == nil)
    }

    @MainActor @Test("Bundling fleet-agent does not designate it without a user choice")
    func bundledFleetAgentRequiresDesignation() throws {
        let suite = "fix-agent-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = FixAgentSettings(defaults: defaults) { name in
            name == "fleet-agent"
                ? URL(fileURLWithPath: "/Applications/FleetConsole.app/Contents/Resources/bin/fleet-agent")
                : nil
        }
        #expect(settings.installed == [.fleetAgent])
        #expect(settings.designated == nil)
        settings.reload()
        #expect(settings.designated == nil)

        defaults.set("codex", forKey: "fleetconsole.fixAgent")
        let missingExternal = FixAgentSettings(defaults: defaults) { name in
            name == "fleet-agent" ? URL(fileURLWithPath: "/bundle/bin/fleet-agent") : nil
        }
        #expect(missingExternal.designated == nil)

        var externalInstalled = false
        let automatic = FixAgentSettings(defaults: defaults) { name in
            name == "fleet-agent" || (name == "claude" && externalInstalled)
                ? URL(fileURLWithPath: "/tools/\(name)") : nil
        }
        #expect(automatic.designated == nil)
        externalInstalled = true
        automatic.reload()
        #expect(automatic.designated == .claude)
    }

    @MainActor @Test("An explicit fleet-agent designation remains selected")
    func explicitFleetAgentDesignationPersists() throws {
        let suite = "fix-agent-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("fleet-agent", forKey: "fleetconsole.fixAgent")
        let settings = FixAgentSettings(defaults: defaults) { name in
            URL(fileURLWithPath: "/bundle/bin/\(name)")
        }
        #expect(settings.designated == .fleetAgent)
        settings.reload()
        #expect(settings.designated == .fleetAgent)
        #expect(defaults.string(forKey: "fleetconsole.fixAgent") == "fleet-agent")
        #expect(FixAgentKind.fleetAgent.title == "Fleet Agent")
    }

    @MainActor @Test("Choosing None stays None after reload and relaunch")
    func explicitNonePersists() throws {
        let suite = "fix-agent-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let resolve: (String) -> URL? = { URL(fileURLWithPath: "/bundle/bin/\($0)") }
        let settings = FixAgentSettings(defaults: defaults, resolve: resolve)
        #expect(settings.designated == .claude)
        settings.designated = nil
        settings.reload()
        #expect(settings.designated == nil)
        let relaunched = FixAgentSettings(defaults: defaults, resolve: resolve)
        #expect(relaunched.designated == nil)
    }

    @Test("The bundled fleet-agent wins over an older PATH binary")
    func bundledBinaryPreferred() throws {
        let resources = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bin = resources.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: resources) }
        let bundled = bin.appendingPathComponent("fleet-agent")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: bundled)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bundled.path)
        var pathLookups: [String] = []
        let resolve: (String) -> URL? = { name in
            pathLookups.append(name)
            return URL(fileURLWithPath: "/old-path/\(name)")
        }
        #expect(FixAgentBinary.resolve("fleet-agent", resourceURL: resources, searchPathResolve: resolve) == bundled)
        #expect(pathLookups.isEmpty)
        #expect(FixAgentBinary.resolve("codex", resourceURL: resources, searchPathResolve: resolve)?.path == "/old-path/codex")
        #expect(pathLookups == ["codex"])
        try FileManager.default.removeItem(at: bundled)
        #expect(FixAgentBinary.resolve("fleet-agent", resourceURL: resources, searchPathResolve: resolve)?.path == "/old-path/fleet-agent")
    }

    @MainActor @Test("The actual handoff uses the resolved binary and saves the complete fleet-agent request")
    func notificationCarriesProposalAndReport() throws {
        let model = AppModel()
        let capture = FixerLaunchCapture()
        let observer = NotificationCenter.default.addObserver(forName: ConsoleCommand.runInTerminal,
                                                              object: nil, queue: .main) { notification in
            let fields = [ConsoleCommand.userInfoCommand, ConsoleCommand.userInfoDirectory,
                          ConsoleCommand.userInfoSubject].reduce(into: [String: String]()) { result, key in
                result[key] = notification.userInfo?[key] as? String
            }
            MainActor.assumeIsolated { capture.notifications.append(fields) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let resources = FileManager.default.temporaryDirectory
            .appendingPathComponent("Fleet's App \(UUID().uuidString)")
        let bin = resources.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: resources) }
        let bundled = bin.appendingPathComponent("fleet-agent")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: bundled)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bundled.path)
        let reportOnDisk = resources.appendingPathComponent("report.md")
        let item = AttentionItem(id: "proposal-test", severity: .critical, title: "fixture problem",
                                 detail: "unique observation: connection refused for worker")
        for kind in [FixAgentKind.fleetAgent, .claude, .codex] {
            let suite = "fix-agent-tests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(kind.rawValue, forKey: "fleetconsole.fixAgent")
            let settings = FixAgentSettings(defaults: defaults) { name in
                FixAgentBinary.resolve(name, resourceURL: resources,
                                       searchPathResolve: { URL(fileURLWithPath: "/external tools/\($0)") })
            }
            var dashboardOpens = 0
            var writtenPath: URL?
            let error = model.sendToFixer([item], openDashboard: { dashboardOpens += 1 }, settings: settings,
                                         loadReportEvents: { $0([]) }, writeReport: { markdown, path in
                writtenPath = path
                try markdown.write(to: reportOnDisk, atomically: true, encoding: .utf8)
            })
            #expect(error == nil)
            #expect(dashboardOpens == 1)
            #expect(model.actionError == nil)
            let notification = try #require(capture.notifications.last)
            let command = try #require(notification[ConsoleCommand.userInfoCommand])
            let written = try String(contentsOf: reportOnDisk, encoding: .utf8)
            #expect(written.contains(item.detail))
            #expect(notification[ConsoleCommand.userInfoSubject] == "\(kind.title) · fixture problem")
            if kind == .fleetAgent {
                let path = try #require(writtenPath)
                #expect(command == bundled.path.shellQuoted + " propose --prompt-file " + path.path.shellQuoted)
                #expect(!command.contains("# FleetConsole fix request"))
                #expect(!command.contains(item.detail))
                #expect(written.contains("read-only tools"))
                #expect(written.hasPrefix(FixReport.proposalPrompt(markdown: "# FleetConsole fix request")))
                #expect(!command.contains("wrote them up at"))
                #expect(!command.hasPrefix("fleet-agent "))
                #expect(!command.contains(" ask "))
            } else {
                let path = try #require(writtenPath)
                #expect(command.hasPrefix("'/external tools/\(kind.rawValue)' "))
                #expect(command.contains(path.path))
                #expect(command.contains("notify --agent \(kind.rawValue)"))
                #expect(!command.contains(item.detail))
            }
        }
        #expect(capture.notifications.count == 3)
    }

    @MainActor @Test("Oversized UTF-8 fleet-agent prompts stop before report writes or notifications")
    func oversizedProposalIsRejected() throws {
        let suite = "fix-agent-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("fleet-agent", forKey: "fleetconsole.fixAgent")
        let settings = FixAgentSettings(defaults: defaults) { name in
            name == "fleet-agent" ? URL(fileURLWithPath: "/bundle/bin/fleet-agent") : nil
        }
        let model = AppModel()
        let capture = FixerLaunchCapture()
        let observer = NotificationCenter.default.addObserver(forName: ConsoleCommand.runInTerminal,
                                                              object: nil, queue: .main) { notification in
            let fields = [ConsoleCommand.userInfoCommand, ConsoleCommand.userInfoDirectory,
                          ConsoleCommand.userInfoSubject].reduce(into: [String: String]()) { result, key in
                result[key] = notification.userInfo?[key] as? String
            }
            MainActor.assumeIsolated { capture.notifications.append(fields) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        var writes = 0
        let item = AttentionItem(id: "oversized", severity: .critical, title: "large report",
                                 detail: String(repeating: "😀", count: 9_000))
        let error = model.sendToFixer([item], openDashboard: {}, settings: settings,
                                     loadReportEvents: { $0([]) }, writeReport: { _, _ in writes += 1 })
        #expect(error == nil)
        #expect(item.detail.count < FixReport.maximumPromptBytes)
        #expect(item.detail.utf8.count > FixReport.maximumPromptBytes)
        #expect(model.actionError?.contains("32 KiB") == true)
        #expect(model.actionError?.contains("no findings were truncated") == true)
        #expect(writes == 0)
        #expect(capture.notifications.isEmpty)
    }

    @MainActor @Test("The fleet-agent prompt accepts exactly 32 KiB and rejects the next byte")
    func proposalByteBoundary() throws {
        let suite = "fix-agent-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("fleet-agent", forKey: "fleetconsole.fixAgent")
        let settings = FixAgentSettings(defaults: defaults) { _ in URL(fileURLWithPath: "/bundle/bin/fleet-agent") }
        let model = AppModel()
        let capture = FixerLaunchCapture()
        let observer = NotificationCenter.default.addObserver(forName: ConsoleCommand.runInTerminal,
                                                              object: nil, queue: .main) { notification in
            let fields = [ConsoleCommand.userInfoCommand, ConsoleCommand.userInfoDirectory,
                          ConsoleCommand.userInfoSubject].reduce(into: [String: String]()) { result, key in
                result[key] = notification.userInfo?[key] as? String
            }
            MainActor.assumeIsolated { capture.notifications.append(fields) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        var item = AttentionItem(id: "boundary", severity: .critical, title: "fixture", detail: "")
        let fixedBytes = FixReport.proposalPrompt(markdown: FixReport.markdown(
            items: [item], services: [], events: [], host: Host.current().localizedName ?? "this Mac")).utf8.count
        item.detail = String(repeating: "a", count: FixReport.maximumPromptBytes - fixedBytes)
        var writes = 0
        model.sendToFixer([item], openDashboard: {}, settings: settings,
                         loadReportEvents: { $0([]) }, writeReport: { _, _ in writes += 1 })
        #expect(model.actionError == nil)
        #expect(writes == 1)
        #expect(capture.notifications.count == 1)
        item.detail += "a"
        model.sendToFixer([item], openDashboard: {}, settings: settings,
                         loadReportEvents: { $0([]) }, writeReport: { _, _ in writes += 1 })
        #expect(model.actionError?.contains("32 KiB") == true)
        #expect(writes == 1)
        #expect(capture.notifications.count == 1)
    }

    @MainActor @Test("A report-write failure prevents terminal dispatch and surfaces the error")
    func failedReportWriteDoesNotLaunch() throws {
        let suite = "fix-agent-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("fleet-agent", forKey: "fleetconsole.fixAgent")
        let settings = FixAgentSettings(defaults: defaults) { _ in URL(fileURLWithPath: "/bundle/bin/fleet-agent") }
        let model = AppModel()
        let capture = FixerLaunchCapture()
        let observer = NotificationCenter.default.addObserver(forName: ConsoleCommand.runInTerminal,
                                                              object: nil, queue: .main) { notification in
            let fields = [ConsoleCommand.userInfoCommand, ConsoleCommand.userInfoDirectory,
                          ConsoleCommand.userInfoSubject].reduce(into: [String: String]()) { result, key in
                result[key] = notification.userInfo?[key] as? String
            }
            MainActor.assumeIsolated { capture.notifications.append(fields) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let item = AttentionItem(id: "write-failure", severity: .critical, title: "fixture", detail: "failure")
        model.sendToFixer([item], openDashboard: {}, settings: settings,
                         loadReportEvents: { $0([]) }, writeReport: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        #expect(model.actionError == "The fix report could not be written.")
        #expect(capture.notifications.isEmpty)
    }

    @Test("The report carries the problem, the service record and its own recent events")
    func reportContents() {
        let service = ServiceRecord(
            id: "svc-search", friendlyName: "search", ownerAgent: "claude",
            purpose: "meilisearch index for notes", command: ["meilisearch", "--db-path", ".meili"],
            cwd: "/Users/fixture/notes", declaredPorts: [7700],
            leaseExpiresAt: Date().addingTimeInterval(3600), leaseTTLSec: 3600, state: .unhealthy,
            stdoutPath: "/tmp/search.out", stderrPath: "/tmp/search.err")
        let item = AttentionItem(id: "att-search", severity: .critical,
                                 title: "search has failed its health check 6 times",
                                 detail: "connection refused", serviceID: "svc-search")
        let events = [
            ServiceEvent(seq: 2, serviceID: "svc-search", serviceName: "search", ts: Date(), kind: .healthFailed,
                         detail: "connection refused"),
            ServiceEvent(seq: 1, serviceID: "svc-other", serviceName: "other", ts: Date(), kind: .healthFailed,
                         detail: "not this one"),
        ]
        let report = FixReport.markdown(items: [item], services: [service], events: events, host: "fixture-mac")
        #expect(report.contains("**Critical: search has failed its health check 6 times**"))
        #expect(report.contains("meilisearch index for notes"))
        #expect(report.contains("`meilisearch --db-path .meili`"))
        #expect(report.contains("`/tmp/search.err`"))
        #expect(report.contains("connection refused"))
        #expect(!report.contains("not this one"))
    }

    @Test("The first turn names the report and the way back to the operator")
    func promptNamesReportAndMailbox() {
        let prompt = FixReport.prompt(reportPath: "/tmp/fix.md", agentID: "claude", fleetctl: "fleetctl")
        #expect(prompt.contains("/tmp/fix.md"))
        #expect(prompt.contains("fleetctl notify --agent claude"))
        #expect(prompt.contains("never signal a process FleetConsole manages directly"))
    }

    @Test("A process is described by what it is, or not at all")
    func processRoles() {
        #expect(ProcessRole.describe(commandLine: "/Applications/Safari.app/Contents/MacOS/Safari",
                                     ports: [], user: "me") == "App · Safari")
        #expect(ProcessRole.describe(commandLine: "python3 -m http.server", ports: [8000], user: "me")
                == "Server · :8000")
        #expect(ProcessRole.describe(commandLine: "/usr/libexec/trustd", ports: [], user: "me")
                == "macOS system process")
        #expect(ProcessRole.describe(commandLine: "node worker.js", ports: [], user: "me") == nil)
    }

    @Test("Catalog prices are shown as the catalog states them")
    func offerPriceLabel() throws {
        let json = #"{"id":"fleet-console-cloud-agent","priceCents":1900,"currency":"usd","interval":"month","intervalCount":1}"#
        let offer = try JSONDecoder().decode(OurosOffer.self, from: Data(json.utf8))
        #expect(offer.priceLabel.contains("19"))
        #expect(offer.priceLabel.hasSuffix("/month"))
        #expect(offer.id == OurosOffer.cloudAgentID)
    }
}

@MainActor
private final class FixerLaunchCapture {
    var notifications: [[String: String]] = []
}
