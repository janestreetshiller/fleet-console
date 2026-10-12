import Foundation
import Testing
import FleetCore
@testable import FleetConsoleApp

struct FixAgentTests {
    @Test("A prompt survives the shell intact, quotes and all")
    func shellQuoting() {
        #expect("plain".shellQuoted == "'plain'")
        #expect("it's \"fine\" $HOME".shellQuoted == #"'it'\''s "fine" $HOME'"#)
    }

    @Test("Each fixer starts on the prompt the way its CLI expects")
    func commandLines() {
        #expect(FixAgentKind.claude.commandLine(prompt: "go") == "claude 'go'")
        #expect(FixAgentKind.codex.commandLine(prompt: "go") == "codex 'go'")
        #expect(FixAgentKind.fleetAgent.commandLine(prompt: "go") == "fleet-agent ask 'go'")
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
