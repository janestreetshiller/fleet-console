import Foundation
import Testing
@testable import FleetConsoleApp

/// All requests terminate here, including unexpected paths. No sockets, keychain,
/// browser, app model, live processes or real credentials are used by this suite.
private final class InvestigationTransportProbe: URLProtocol, @unchecked Sendable {
    enum Scenario: Sendable, Equatable {
        case ready, notRunnable, catalogDenied, catalogUnauthorized, malformedCatalog, completionDenied
        case malformedCompletion, oversizedCompletion, timeoutCompletion, heldCompletion
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var scenario: Scenario = .ready
    nonisolated(unsafe) private static var recorded: [URLRequest] = []
    nonisolated(unsafe) private static var held: (@Sendable () -> Void)?
    static var hasHeldCompletion: Bool { lock.withLock { held != nil } }
    static func releaseHeldCompletion() {
        let deliver = lock.withLock { let value = held; held = nil; return value }
        deliver?()
    }
    static let syntheticToken = String(repeating: "T", count: 43)

    static var requests: [URLRequest] { lock.withLock { recorded } }
    static func reset(_ next: Scenario = .ready) {
        lock.withLock { scenario = next; recorded = []; held = nil }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var snapshot = request
        if snapshot.httpBody == nil, let stream = snapshot.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable && data.count <= 16_384 {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            snapshot.httpBody = data
        }
        let selected = Self.lock.withLock {
            Self.recorded.append(snapshot)
            return Self.scenario
        }
        guard request.url?.host == "ouros.md", let path = request.url?.path else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        var status = 200
        let body: [String: Any]
        switch path {
        case "/auth/device/code":
            body = ["device_code": "synthetic-only-grant", "user_code": "ABCD-EFGH",
                    "verification_uri_complete": "https://ouros.md/auth/device/verify?synthetic=true",
                    "expires_in": 60, "interval": 5]
        case "/auth/device/token":
            body = ["access_token": Self.syntheticToken, "token_type": "Bearer", "expires_in": 3600]
        case "/hvy/v1/fleet-console/entitlement":
            // A runnable agent must not depend on this multi-device-only flag.
            body = ["accountID": "synthetic-only-account", "active": false, "periodEnd": NSNull()]
        case "/hvy/v1/fleet-console/offers":
            body = ["configured": false, "offers": []]
        case "/ouros/v1/models":
            switch selected {
            case .catalogDenied:
                status = 403; body = ["code": "scope_forbidden"]
            case .catalogUnauthorized:
                status = 401; body = ["code": "invalid_session"]
            case .malformedCatalog:
                body = ["ok": true, "runnable": true, "models": "invalid"]
            case .notRunnable:
                body = ["ok": true, "runnable": false, "code": "subscription_required", "models": []]
            default:
                body = ["ok": true, "runnable": true, "defaultModelId": "synthetic-model",
                        "models": [["id": "synthetic-model"]]]
            }
        case "/v1/chat/completions":
            switch selected {
            case .completionDenied:
                status = 402; body = ["error": ["code": "subscription_required"]]
            case .malformedCompletion:
                body = ["choices": []]
            case .oversizedCompletion:
                body = ["choices": [["message": ["content": String(repeating: "x", count: 70_000)]]]]
            case .timeoutCompletion:
                client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return
            default:
                body = ["choices": [["message": ["content": "Synthetic snapshot analysis only."]]]]
            }
        default:
            // This fixture deliberately has no live-network fallback.
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                              headerFields: ["Content-Type": "application/json"]),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotDecodeContentData)); return
        }
        let deliver: @Sendable () -> Void = { [self] in
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        if path == "/v1/chat/completions", selected == .heldCompletion {
            Self.lock.withLock { Self.held = deliver }
        } else { deliver() }
    }
}

@Suite(.serialized)
struct InvestigationTransportTests {
    private static let pendingKey = "fleetconsole.investigation.unconfirmed.v1"
    private static let starter = #"{"schemaVersion":1,"subject":"cpu","values":{"utilizationFraction":0.75}}"#

    @MainActor private func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InvestigationTransportProbe.self]
        return config
    }
    @MainActor private func fixture(defaults: UserDefaults, authenticated: Bool = true) -> OurosBilling {
        let token = authenticated ? OurosCredential(token: InvestigationTransportProbe.syntheticToken,
                                                   expires: Date().addingTimeInterval(3600)) : nil
        return OurosBilling(credentialStore: TestOurosCredentialStore(token), sessionConfiguration: configuration(),
                     operationDefaults: defaults, openBrowser: { _ in })
    }
    @MainActor private func expectRefusal(_ operation: @MainActor () async throws -> String) async {
        do { _ = try await operation(); Issue.record("Expected a refused or unconfirmed investigation") }
        catch { #expect(error is InvestigationGatewayError) }
    }
    private func body(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        let stream = try #require(request.httpBodyStream)
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
            #expect(data.count <= 16_384)
            if data.count > 16_384 { break }
        }
        return data
    }

    @MainActor @Test func unsignedAccountNeverDispatches() async throws {
        InvestigationTransportProbe.reset()
        let suite = "FleetInvestigationTransport.unsigned." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let billing = fixture(defaults: defaults, authenticated: false)
        await expectRefusal { try await billing.investigate(starter: Self.starter, validateObservation: { true }) }
        #expect(InvestigationTransportProbe.requests.isEmpty)
    }

    /// Explicit synthetic credentials avoid device login, polling and Keychain.
    /// All requests in this serial matrix terminate in the private URLProtocol.
    @MainActor @Test func entitledTransportAndAmbiguousOutcomeMatrix() async throws {
        InvestigationTransportProbe.reset()
        let suite = "FleetInvestigationTransport.matrix." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let billing = fixture(defaults: defaults)
        #expect(billing.signedIn)
        #expect(!billing.active)

        InvestigationTransportProbe.reset()
        let reply = try await billing.investigate(starter: Self.starter, validateObservation: { true })
        #expect(reply == "Synthetic snapshot analysis only.")
        #expect(InvestigationTransportProbe.requests.map { $0.url!.path } == ["/ouros/v1/models", "/v1/chat/completions"])
        let sent = try #require(InvestigationTransportProbe.requests.last)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer " + InvestigationTransportProbe.syntheticToken)
        #expect(UUID(uuidString: try #require(sent.value(forHTTPHeaderField: "Idempotency-Key"))) != nil)
        let object = try #require(JSONSerialization.jsonObject(with: body(sent)) as? [String: Any])
        #expect(object["model"] as? String == "synthetic-model")
        #expect(object["tools"] == nil)
        let messages = try #require(object["messages"] as? [[String: String]])
        #expect(messages.last?["content"] == Self.starter)
        #expect(defaults.string(forKey: Self.pendingKey) == nil)

        for scenario in [InvestigationTransportProbe.Scenario.notRunnable, .catalogDenied, .malformedCatalog] {
            InvestigationTransportProbe.reset(scenario)
            await expectRefusal { try await billing.investigate(starter: Self.starter, validateObservation: { true }) }
            #expect(InvestigationTransportProbe.requests.map { $0.url!.path } == ["/ouros/v1/models"])
            #expect(billing.unconfirmedInvestigationID == nil)
        }
        InvestigationTransportProbe.reset()
        await expectRefusal { try await billing.investigate(starter: Self.starter, validateObservation: { false }) }
        #expect(InvestigationTransportProbe.requests.map { $0.url!.path } == ["/ouros/v1/models"])

        InvestigationTransportProbe.reset(.completionDenied)
        await expectRefusal { try await billing.investigate(starter: Self.starter, validateObservation: { true }) }
        #expect(billing.unconfirmedInvestigationID == nil)
        #expect(defaults.string(forKey: Self.pendingKey) == nil)

        for scenario in [InvestigationTransportProbe.Scenario.malformedCompletion, .oversizedCompletion, .timeoutCompletion] {
            InvestigationTransportProbe.reset(scenario)
            await expectRefusal { try await billing.investigate(starter: Self.starter, validateObservation: { true }) }
            let outstanding = try #require(billing.unconfirmedInvestigationID)
            #expect(defaults.string(forKey: Self.pendingKey) == outstanding)
            #expect(fixture(defaults: defaults).unconfirmedInvestigationID == outstanding)
            let before = InvestigationTransportProbe.requests.count
            await expectRefusal { try await billing.investigate(starter: Self.starter, validateObservation: { true }) }
            #expect(InvestigationTransportProbe.requests.count == before)
            billing.acknowledgeUnconfirmedInvestigation()
            #expect(billing.unconfirmedInvestigationID == nil)
            #expect(InvestigationTransportProbe.requests.count == before)
        }

        InvestigationTransportProbe.reset(.heldCompletion)
        let first = Task { @MainActor in try await billing.investigate(starter: Self.starter, validateObservation: { true }) }
        defer { first.cancel(); InvestigationTransportProbe.releaseHeldCompletion() }
        for _ in 0..<1_000 {
            if InvestigationTransportProbe.hasHeldCompletion { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        guard InvestigationTransportProbe.hasHeldCompletion else {
            Issue.record("Synthetic completion did not reach the controlled fixture in one second")
            return
        }
        #expect(billing.busy)
        await expectRefusal { try await billing.investigate(starter: Self.starter, validateObservation: { true }) }
        InvestigationTransportProbe.releaseHeldCompletion()
        _ = try await first.value
        #expect(InvestigationTransportProbe.requests.map { $0.url!.path } == ["/ouros/v1/models", "/v1/chat/completions"])

        InvestigationTransportProbe.reset(.catalogUnauthorized)
        await expectRefusal { try await billing.investigate(starter: Self.starter, validateObservation: { true }) }
        #expect(!billing.signedIn)
        #expect(InvestigationTransportProbe.requests.map { $0.url!.path } == ["/ouros/v1/models"])
    }
}
