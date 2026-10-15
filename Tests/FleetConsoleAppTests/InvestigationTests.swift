import Foundation
import Testing
@testable import FleetConsoleApp

struct InvestigationTests {
    @Test func snapshotFreshnessDoesNotRewriteObservationTime() {
        let observed = Date(timeIntervalSince1970: 1_000)
        let request = InvestigationRequest(kind: "metric", subject: "cpu", observedAt: observed,
                                          values: ["utilizationFraction": 0.75], context: [:], processes: [])
        #expect(request.isFresh(at: observed.addingTimeInterval(30)))
        #expect(!request.isFresh(at: observed.addingTimeInterval(31)))
        #expect(!request.isFresh(at: observed.addingTimeInterval(-1)))
        let absent = InvestigationRequest(kind: "metric", subject: "memory", observedAt: nil,
                                         values: [:], context: [:], processes: [])
        #expect(!absent.isFresh(at: observed))
    }

    @Test func historicalContextRemainsExplicitlyHistorical() throws {
        let observed = Date(timeIntervalSince1970: 1_000)
        let request = InvestigationRequest(kind: "historical-process", subject: "pid 42", observedAt: observed,
                                          values: [:], context: ["scope": "historical; PID is not current"], processes: [])
        #expect(request.isFresh(at: observed.addingTimeInterval(300)))
        #expect(!request.isFresh(at: observed.addingTimeInterval(3_601)))
        #expect(try request.starter().contains("historical-process"))
    }

    @Test func jsonEscapesTerminalAndShellControlText() throws {
        let untrusted = "quote\" newline\n escape\u{1B} $(touch /tmp/never) `whoami`"
        let request = InvestigationRequest(kind: "metric", subject: "cpu", observedAt: Date(),
                                          values: [:], context: ["untrusted": untrusted], processes: [])
        let starter = try request.starter()
        #expect(!starter.contains("\u{1B}"))
        let start = try #require(starter.firstIndex(of: "{"))
        let object = try #require(JSONSerialization.jsonObject(with: Data(starter[start...].utf8)) as? [String: Any])
        let context = try #require(object["context"] as? [String: String])
        #expect(context["untrusted"] == untrusted)
        #expect((object["permission"] as? String)?.contains("no termination") == true)
    }

    @Test func argvCredentialsAndPathsNeverEnterProcessEvidence() throws {
        let row = ProcessRow(id: 42, pid: 42, ppid: 1, pgid: 42, uid: 501,
                             user: "private-user", name: "/private/project/codex",
                             commandLine: "codex --api-key TOP_SECRET_VALUE https://user:password@example.com",
                             cpuPercent: .nan, residentBytes: 1_024, ports: Array(1...100),
                             startSignature: "Thu Oct 15 12:00:00 2026", stateField: "R")
        let evidence = InvestigationRequest.ProcessEvidence(row)
        let data = try JSONEncoder().encode(evidence)
        let json = String(decoding: data, as: UTF8.self)
        #expect(evidence.cpuPercent == nil)
        #expect(evidence.listeningPorts.count == 16)
        #expect(evidence.executable == "codex")
        #expect(!json.contains("TOP_SECRET_VALUE"))
        #expect(!json.contains("private-user"))
        #expect(!json.contains("private/project"))
        #expect(!json.contains("example.com"))
        #expect(InvestigationRequest.label("sk-supersecret") == "[redacted]")
    }

    @Test func oversizedAndNonfiniteContextFailClosed() {
        let huge = InvestigationRequest(kind: "metric", subject: "cpu", observedAt: Date(),
                                        values: [:], context: ["oversized": String(repeating: "x", count: 20_000)], processes: [])
        #expect(throws: (any Error).self) { try huge.starter() }
        let nonfinite = InvestigationRequest(kind: "metric", subject: "cpu", observedAt: Date(),
                                             values: ["invalid": .infinity], context: [:], processes: [])
        #expect(throws: (any Error).self) { try nonfinite.starter() }
    }
    @Test func gatewayUsesExistingServerAuthorizedTextContract() throws {
        let payload = try InvestigationGatewayPayload.make(model: "catalog-model", starter: "{\"subject\":\"cpu\"}")
        let object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(object["model"] as? String == "catalog-model")
        #expect(object["stream"] as? Bool == false)
        #expect(object["tools"] == nil)
        let messages = try #require(object["messages"] as? [[String: String]])
        #expect(messages.count == 2)
        #expect(messages.last?["content"] == "{\"subject\":\"cpu\"}")
        #expect(payload.count <= 16_384)
        #expect(throws: (any Error).self) {
            try InvestigationGatewayPayload.make(model: "catalog-model", starter: String(repeating: "x", count: 17_000))
        }
    }

    @Test func uncertainGatewayFailuresNeverPermitBlindReplay() {
        let upstream = Data("{\"error\":{\"code\":\"upstream_error\"}}".utf8)
        #expect(!InvestigationGatewayPayload.refusedBeforeDispatch(data: upstream, status: 400))
        #expect(!InvestigationGatewayPayload.refusedBeforeDispatch(data: upstream, status: 422))
        #expect(!InvestigationGatewayPayload.refusedBeforeDispatch(data: upstream, status: 429))
        #expect(!InvestigationGatewayPayload.refusedBeforeDispatch(data: upstream, status: 502))
        let denied = Data("{\"code\":\"subscription_required\"}".utf8)
        #expect(InvestigationGatewayPayload.refusedBeforeDispatch(data: denied, status: 402))
    }

}
