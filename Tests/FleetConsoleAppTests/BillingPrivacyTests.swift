import Foundation
import Testing
@testable import FleetConsoleApp

private final class BillingRequestProbe: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var recorded: [URLRequest] = []
    static var requests: [URLRequest] { lock.withLock { recorded } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.recorded.append(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        let body: [String: Any]
        switch request.url!.path {
        case "/auth/device/code":
            body = ["device_code": "synthetic-grant", "user_code": "ABCD-EFGH", "verification_uri_complete": "https://ouros.md/auth/device/verify?fixture=true", "expires_in": 60, "interval": 5]
        case "/auth/device/token":
            body = ["access_token": String(repeating: "T", count: 43), "token_type": "Bearer", "expires_in": 3600]
        case "/hvy/v1/fleet-console/entitlement":
            body = ["accountID": "synthetic-account", "active": false, "periodEnd": NSNull()]
        default:
            body = ["configured": true, "offers": [["id": "fleet-console-multi-device", "priceCents": 1000, "currency": "usd", "interval": "month", "intervalCount": 1]]]
        }
        let data = try! JSONSerialization.data(withJSONObject: body)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct BillingPrivacyTests {
    @MainActor private func configuration() -> URLSessionConfiguration {
        BillingRequestProbe.lock.withLock { BillingRequestProbe.recorded = [] }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BillingRequestProbe.self]
        return configuration
    }

    @MainActor @Test func cloudRequestsStartWithExplicitBillingInteraction() async {
        let billing = OurosBilling(useKeychain: false, sessionConfiguration: configuration(), openBrowser: { _ in })
        await billing.refresh()
        await billing.refresh()
        #expect(BillingRequestProbe.requests.isEmpty)
        #expect(!billing.available)
        await billing.refresh(userInitiated: true)
        #expect(BillingRequestProbe.requests.count == 1)
        #expect(BillingRequestProbe.requests.first?.url?.path == "/hvy/v1/fleet-console/offers")
        #expect(BillingRequestProbe.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(billing.available)
        await billing.refresh()
        #expect(BillingRequestProbe.requests.count == 1)
    }

    @MainActor @Test func firstAccountConnectionLoadsOffersAndEnablesSignedInRefresh() async throws {
        var opened: [URL] = []
        let billing = OurosBilling(useKeychain: false, sessionConfiguration: configuration(), openBrowser: { opened.append($0) })
        let task = try #require(billing.connect())
        await task.value
        #expect(billing.signedIn)
        #expect(billing.available)
        #expect(!billing.busy)
        #expect(opened.count == 1)
        #expect(BillingRequestProbe.requests.map { $0.url!.path }.contains("/hvy/v1/fleet-console/offers"))
        let before = BillingRequestProbe.requests.count
        await billing.refresh()
        #expect(BillingRequestProbe.requests.count == before + 2)
        #expect(BillingRequestProbe.requests.last?.url?.path == "/hvy/v1/fleet-console/entitlement")
        #expect(BillingRequestProbe.requests.last?.value(forHTTPHeaderField: "Authorization") != nil)
    }

    @MainActor @Test func signedOutExplicitRefreshExplainsHowToRecoverAnExistingPurchase() async {
        let billing = OurosBilling(useKeychain: false, sessionConfiguration: configuration(), openBrowser: { _ in })
        await billing.refresh(userInitiated: true)
        #expect(billing.available)
        #expect(!billing.signedIn)
        #expect(!billing.active)
        #expect(billing.message == "Sign in to check your subscription. If you already paid, use the same Ouros account.")
        #expect(BillingRequestProbe.requests.map { $0.url!.path } == ["/hvy/v1/fleet-console/offers"])
    }
}
