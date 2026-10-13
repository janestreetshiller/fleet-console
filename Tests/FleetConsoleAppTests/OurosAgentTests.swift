import Foundation
import Testing
import FleetCore
@testable import FleetConsoleApp

@MainActor
struct OurosAgentTests {
    private func service(claimed: Bool = false) -> ServiceRecord {
        var record = ServiceRecord(id: "svc", friendlyName: "fixture", ownerAgent: "fixture",
            purpose: "test", command: ["fixture"], cwd: "/tmp", leaseExpiresAt: Date().addingTimeInterval(600), leaseTTLSec: 600)
        record.claimed = claimed
        return record
    }

    private func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func catalog() throws -> Data {
        try data(["runnable": true, "defaultModelId": "gemini-fixture", "models": [["id": "gemini-fixture", "tools": true]]])
    }

    @Test func toolsPreserveOpaqueSignaturesAndOnlyProposeManagedRestarts() async throws {
        var bodies: [[String: Any]] = [], keys: [String] = []
        let signature = "opaque-fixture-signature"
        let agent = OurosAgent { path, method, body, key in
            if path == "/ouros/v1/models" { return try catalog() }
            #expect(path == "/v1/chat/completions" && method == "POST")
            let bytes = try #require(body)
            let request = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            bodies.append(request); keys.append(try #require(key))
            if bodies.count == 1 {
                return try data(["usage": ["cost": 0.0001], "choices": [["message": ["role": "assistant", "content": NSNull(),
                    "tool_calls": [["id": "read", "type": "function", "function": ["name": "get_service", "arguments": "{\"service_id\":\"svc\"}"], "extra_content": ["google": ["thought_signature": signature]]]]]]]])
            }
            if bodies.count == 2 {
                let messages = try #require(request["messages"] as? [[String: Any]])
                let calls = try #require(messages[2]["tool_calls"] as? [[String: Any]])
                let extra = try #require(calls[0]["extra_content"] as? [String: Any])
                #expect((extra["google"] as? [String: String])?["thought_signature"] == signature)
                #expect(messages.last?["tool_call_id"] as? String == "read")
                return try data(["usage": ["cost": 0.0002], "choices": [["message": ["role": "assistant",
                    "tool_calls": [["id": "restart", "type": "function", "function": ["name": "propose_restart", "arguments": "{\"service_id\":\"svc\"}"]]]]]]])
            }
            return try data(["usage": ["cost": 0.0003], "choices": [["message": ["role": "assistant", "content": "A restart is awaiting your approval."]]]])
        }
        await agent.review(report: "fixture report", services: [service()])
        #expect(agent.proposedRestarts == ["svc"])
        #expect(agent.answer.contains("awaiting"))
        #expect(abs(agent.chargedUSD - 0.0006) < 0.00000001)
        #expect(keys.count == 3 && Set(keys).count == 3)
        #expect(agent.elapsed > 0 && !agent.busy && agent.message == nil)
    }

    @Test func depletedCreditDoesNotRetry() async throws {
        var calls = 0
        let agent = OurosAgent { path, _, _, _ in
            if path == "/ouros/v1/models" { return try catalog() }
            calls += 1; throw OurosFailure.server("insufficient_allowance")
        }
        await agent.review(report: "fixture", services: [])
        #expect(calls == 1)
        #expect(agent.message?.contains("Add usage credits") == true)
        #expect(agent.chargedUSD == 0)
    }

    @Test func ambiguousResponseDoesNotDispatchAgain() async throws {
        var calls = 0
        let agent = OurosAgent { path, _, _, _ in
            if path == "/ouros/v1/models" { return try catalog() }
            calls += 1; throw URLError(.networkConnectionLost)
        }
        await agent.review(report: "fixture", services: [])
        await agent.review(report: "fixture", services: [])
        #expect(calls == 1 && agent.requests.count == 1 && agent.pendingKey != nil)
        #expect(agent.message?.contains("Check billing") == true)
    }

    @Test func claimedServicesCannotBeProposedForRestartAndRoundsAreBounded() async throws {
        var calls = 0
        let agent = OurosAgent { path, _, body, _ in
            if path == "/ouros/v1/models" { return try catalog() }
            calls += 1
            if calls > 1 {
                let bytes = try #require(body)
            let request = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                let messages = try #require(request["messages"] as? [[String: Any]])
                #expect((messages.last?["content"] as? String)?.contains("tool_or_service_not_allowed") == true)
            }
            return try data(["usage": ["cost": 0.001], "choices": [["message": ["role": "assistant",
                "tool_calls": [["id": "round-\(calls)", "type": "function", "function": ["name": "propose_restart", "arguments": "{\"service_id\":\"svc\"}"]]]]]]])
        }
        await agent.review(report: "fixture", services: [service(claimed: true)])
        #expect(calls == 4 && agent.proposedRestarts.isEmpty)
        #expect(agent.message?.contains("four model requests") == true)
    }

    @Test func missingUsageFailsWithoutInventingZeroCharge() async throws {
        var calls = 0
        let agent = OurosAgent { path, _, _, _ in
            if path == "/ouros/v1/models" { return try catalog() }
            calls += 1
            return try data(["choices": [["message": ["role": "assistant", "content": "unpriced"]]]])
        }
        await agent.review(report: "fixture", services: [])
        #expect(calls == 1 && agent.answer.isEmpty)
        #expect(agent.message != nil)
    }
    @Test func checkingAnUncertainRequestKeepsItsOriginalBodyAndKey() async throws {
        var requests: [(Data, String)] = []
        let agent = OurosAgent { path, _, body, key in
            if path == "/ouros/v1/models" { return try catalog() }
            requests.append((try #require(body), try #require(key)))
            if requests.count == 1 { throw URLError(.networkConnectionLost) }
            throw OurosFailure.server("already_settled")
        }
        await agent.review(report: "fixture", services: [])
        #expect(agent.pendingKey != nil)
        agent.checkPending()
        for _ in 0..<100 { if requests.count == 2 && !agent.busy { break }; await Task.yield() }
        #expect(requests.count == 2)
        #expect(requests[0].0 == requests[1].0 && requests[0].1 == requests[1].1)
        #expect(agent.pendingKey == nil && agent.message?.contains("settled") == true)
    }

    @Test func cancellingRetainsTheOriginalPaidOperationWithoutRetry() async throws {
        var calls = 0
        let agent = OurosAgent { path, _, _, _ in
            if path == "/ouros/v1/models" { return try catalog() }
            calls += 1
            try await Task.sleep(for: .seconds(60))
            throw OurosFailure.invalidResponse
        }
        agent.start(report: "fixture", services: [])
        for _ in 0..<100 { if calls == 1 { break }; await Task.yield() }
        #expect(calls == 1)
        agent.cancel()
        for _ in 0..<100 { if !agent.busy { break }; await Task.yield() }
        #expect(!agent.busy && agent.pendingKey != nil)
        #expect(agent.message?.contains("Stopped") == true)
        await agent.review(report: "fixture", services: [])
        #expect(calls == 1)
    }

    @Test func uncertainOperationSurvivesRestartAndStaysAccountScoped() async throws {
        let suite = "fleet-agent-journal-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var originalBody: Data?, originalKey: String?
        let first = OurosAgent(journal: defaults, journalKey: "account-one") { path, _, body, key in
            if path == "/ouros/v1/models" { return try catalog() }
            originalBody = body; originalKey = key; throw URLError(.networkConnectionLost)
        }
        await first.review(report: "fixture", services: [])
        #expect(first.pendingKey != nil)
        let second = OurosAgent(journal: defaults, journalKey: "account-one") { _, _, body, key in
            #expect(body == originalBody && key == originalKey)
            throw OurosFailure.server("already_settled")
        }
        #expect(second.pendingKey == originalKey)
        let other = OurosAgent(journal: defaults, journalKey: "account-two") { _, _, _, _ in
            Issue.record("other account must not read or retry the pending request")
            throw OurosFailure.invalidResponse
        }
        #expect(other.pendingKey == nil)
        second.checkPending()
        for _ in 0..<100 { if second.pendingKey == nil { break }; await Task.yield() }
        #expect(second.pendingKey == nil && defaults.dictionary(forKey: "account-one") == nil)
    }

}
