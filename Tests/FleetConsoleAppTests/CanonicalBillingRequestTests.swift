import Foundation
import Testing
@testable import FleetConsoleApp

private struct CanonicalBillingReceipt: @unchecked Sendable {
    let request: URLRequest
    let body: [String: String]?
}

/// A strict transport fixture: historical routes and invented routes return 404.
/// It intercepts every request; no device grant, payment or browser is created.
private final class CanonicalBillingProtocol: URLProtocol, @unchecked Sendable {
    enum Scenario { case normal, deniedToken, unauthorizedEntitlement, unsafeLinks, redirectedOffers }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [CanonicalBillingReceipt] = []
    nonisolated(unsafe) private static var scenario: Scenario = .normal
    nonisolated(unsafe) private static var paid = false
    nonisolated(unsafe) private static var completeCheckout = false
    nonisolated(unsafe) private static var identity = ""

    static var receipts: [CanonicalBillingReceipt] { lock.withLock { recorded } }
    static var accountID: String { lock.withLock { identity } }
    static func configure(_ value: Scenario) {
        lock.withLock {
            recorded = []; scenario = value; paid = false; completeCheckout = false
            identity = "canonical-test-" + UUID().uuidString
        }
    }
    static func clearReceipts() { lock.withLock { recorded = [] } }
    static func finishCheckout() { lock.withLock { completeCheckout = true; paid = true } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    private func requestBody() -> [String: String]? {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 1024)
            var collected = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                collected.append(contentsOf: bytes.prefix(count))
            }
            data = collected
        }
        return data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
    }

    override func startLoading() {
        let receipt = CanonicalBillingReceipt(request: request, body: requestBody())
        let state = Self.lock.withLock {
            Self.recorded.append(receipt)
            return (Self.scenario, Self.paid, Self.completeCheckout, Self.identity)
        }
        var status = 200
        var headers = ["Content-Type": "application/json"]
        let body: [String: Any]
        switch (request.httpMethod, request.url?.path) {
        case ("POST", "/auth/device/code"):
            body = ["device_code": "synthetic-canonical-grant", "user_code": "ABCD-EFGH",
                    "verification_uri_complete": "https://ouros.md/auth/device/verify?fixture=true",
                    "expires_in": 60, "interval": 5]
        case ("POST", "/auth/device/token"):
            if state.0 == .deniedToken { status = 400; body = ["error": "access_denied"] }
            else { body = ["access_token": String(repeating: "T", count: 43), "token_type": "Bearer", "expires_in": 3600] }
        case ("GET", "/ouros/v1/fleet-console/offers"):
            if state.0 == .redirectedOffers {
                status = 302; headers["Location"] = "https://untrusted.invalid/offers"; body = [:]
            } else {
                body = ["configured": true, "offers": [["id": "fleet-console-multi-device",
                        "priceCents": 1000, "currency": "usd", "interval": "month", "intervalCount": 1]]]
            }
        case ("GET", "/ouros/v1/fleet-console/entitlement"):
            if state.0 == .unauthorizedEntitlement { status = 401; body = ["code": "authentication_required"] }
            else {
                body = ["accountID": state.3, "active": state.1,
                        "periodEnd": Date().addingTimeInterval(3600).timeIntervalSince1970]
            }
        case ("POST", "/ouros/v1/fleet-console/checkout"):
            if state.2 { body = ["state": "complete"] }
            else { body = ["url": state.0 == .unsafeLinks ? "https://checkout.stripe.com.untrusted.invalid/pay"
                          : "https://checkout.stripe.com/c/pay/synthetic-canonical-checkout"] }
        case ("POST", "/ouros/v1/fleet-console/portal"):
            body = ["url": state.0 == .unsafeLinks ? "https://billing.stripe.com.untrusted.invalid/portal"
                    : "https://billing.stripe.com/p/session/synthetic-canonical-portal"]
        case ("POST", "/auth/logout"):
            body = ["ok": true]
        default:
            status = 404; body = ["code": "unexpected_route"]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized)
struct CanonicalBillingRequestTests {
    @MainActor private func billing(_ scenario: CanonicalBillingProtocol.Scenario = .normal,
                                    browser: @escaping (URL) -> Void = { _ in }) -> OurosBilling {
        CanonicalBillingProtocol.configure(scenario)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CanonicalBillingProtocol.self]
        return OurosBilling(useKeychain: false, sessionConfiguration: configuration, openBrowser: browser)
    }

    private func assertAuthenticated(_ receipt: CanonicalBillingReceipt) {
        #expect(receipt.request.url?.scheme == "https")
        #expect(receipt.request.url?.host == "ouros.md")
        #expect(receipt.request.value(forHTTPHeaderField: "Authorization") == "Bearer " + String(repeating: "T", count: 43))
        #expect(receipt.request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(receipt.request.value(forHTTPHeaderField: "Origin") == nil)
    }

    @MainActor @Test func issuedTokenImmediatelyChecksCanonicalEntitlementThenRefreshes() async throws {
        var opened: [URL] = []
        let client = billing(browser: { opened.append($0) })
        await (try #require(client.connect())).value
        #expect(client.signedIn)
        #expect(client.available)
        #expect(client.membership?.accountID == CanonicalBillingProtocol.accountID)
        let connection = CanonicalBillingProtocol.receipts
        #expect(connection.map { $0.request.url!.path } == ["/auth/device/code", "/auth/device/token",
                "/ouros/v1/fleet-console/entitlement", "/ouros/v1/fleet-console/offers"])
        #expect(connection.first?.body == ["client_id": "ouros-desktop"])
        #expect(connection.dropFirst().first?.body == ["client_id": "ouros-desktop", "device_code": "synthetic-canonical-grant",
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
        for receipt in connection where receipt.request.url?.path.hasSuffix("/entitlement") == true { assertAuthenticated(receipt) }
        #expect(connection.last?.request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(opened.map(\.path) == ["/auth/device/verify"])
        CanonicalBillingProtocol.clearReceipts()
        await client.refresh(userInitiated: true)
        let refreshed = CanonicalBillingProtocol.receipts
        #expect(refreshed.map { $0.request.url!.path } == ["/ouros/v1/fleet-console/offers", "/ouros/v1/fleet-console/entitlement"])
        #expect(refreshed.first?.request.value(forHTTPHeaderField: "Authorization") == nil)
        for receipt in refreshed where receipt.request.url?.path.hasSuffix("/entitlement") == true { assertAuthenticated(receipt) }
        #expect(!client.active)
    }

    @MainActor @Test func checkoutPortalCompletionAndLogoutPreserveTheirContracts() async throws {
        var opened: [URL] = []
        let client = billing(browser: { opened.append($0) })
        defer { UserDefaults.standard.removeObject(forKey: "fleetconsole.ouros.checkout." + CanonicalBillingProtocol.accountID) }
        await (try #require(client.connect())).value
        CanonicalBillingProtocol.clearReceipts()
        await client.subscribe()
        await client.subscribe()
        await client.manage()
        let purchasing = CanonicalBillingProtocol.receipts
        #expect(purchasing.map { $0.request.url!.path } == ["/ouros/v1/fleet-console/checkout",
                "/ouros/v1/fleet-console/checkout", "/ouros/v1/fleet-console/portal"])
        for receipt in purchasing { assertAuthenticated(receipt); #expect(receipt.request.httpMethod == "POST") }
        let checkouts = purchasing.filter { $0.request.url?.path.hasSuffix("/checkout") == true }
        #expect(checkouts.count == 2)
        #expect(checkouts.allSatisfy { $0.body == ["offerId": "fleet-console-multi-device"] })
        #expect(checkouts.first?.request.value(forHTTPHeaderField: "Idempotency-Key")?.isEmpty == false)
        #expect(checkouts.first?.request.value(forHTTPHeaderField: "Idempotency-Key") == checkouts.last?.request.value(forHTTPHeaderField: "Idempotency-Key"))
        #expect(purchasing.last?.body == [:])
        #expect(opened.map(\.host) == ["ouros.md", "checkout.stripe.com", "checkout.stripe.com", "billing.stripe.com"])
        CanonicalBillingProtocol.finishCheckout()
        CanonicalBillingProtocol.clearReceipts()
        await client.subscribe()
        #expect(CanonicalBillingProtocol.receipts.map { $0.request.url!.path } == ["/ouros/v1/fleet-console/checkout", "/ouros/v1/fleet-console/entitlement"])
        CanonicalBillingProtocol.receipts.forEach(assertAuthenticated)
        #expect(client.active)
        CanonicalBillingProtocol.clearReceipts()
        await client.disconnect()
        #expect(CanonicalBillingProtocol.receipts.map { $0.request.url!.path } == ["/auth/logout"])
        CanonicalBillingProtocol.receipts.forEach(assertAuthenticated)
        #expect(CanonicalBillingProtocol.receipts.first?.body == [:])
        #expect(!client.signedIn)
        #expect(!client.active)
    }

    @MainActor @Test func deniedApprovalNeverReachesBilling() async throws {
        let client = billing(.deniedToken)
        await (try #require(client.connect())).value
        #expect(!client.signedIn)
        #expect(client.message == "Account connection was denied. Connect again when you are ready.")
        #expect(CanonicalBillingProtocol.receipts.map { $0.request.url!.path } == ["/auth/device/code", "/auth/device/token"])
    }

    @MainActor @Test func unauthorizedEntitlementClearsSessionAndBlocksPurchases() async throws {
        let client = billing(.unauthorizedEntitlement)
        await (try #require(client.connect())).value
        #expect(!client.signedIn)
        #expect(!client.active)
        #expect(client.message == "Connect your Ouros account to continue.")
        #expect(CanonicalBillingProtocol.receipts.map { $0.request.url!.path } == ["/auth/device/code", "/auth/device/token", "/ouros/v1/fleet-console/entitlement"])
        CanonicalBillingProtocol.clearReceipts()
        await client.subscribe(); await client.manage()
        #expect(CanonicalBillingProtocol.receipts.isEmpty)
    }

    @MainActor @Test func untrustedCheckoutAndPortalURLsNeverOpen() async throws {
        var opened: [URL] = []
        let client = billing(.unsafeLinks, browser: { opened.append($0) })
        defer { UserDefaults.standard.removeObject(forKey: "fleetconsole.ouros.checkout." + CanonicalBillingProtocol.accountID) }
        await (try #require(client.connect())).value
        await client.subscribe(); await client.manage()
        #expect(opened.map(\.host) == ["ouros.md"])
        #expect(client.message == "Ouros could not complete the request. Try again.")
        #expect(CanonicalBillingProtocol.receipts.suffix(2).map { $0.request.url!.path } == ["/ouros/v1/fleet-console/checkout", "/ouros/v1/fleet-console/portal"])
    }

    @MainActor @Test func unsignedCatalogRemainsExplicitAndRedirectsAreRejected() async {
        var opened: [URL] = []
        let client = billing(.redirectedOffers, browser: { opened.append($0) })
        await client.refresh()
        #expect(CanonicalBillingProtocol.receipts.isEmpty)
        await client.refresh(userInitiated: true)
        #expect(CanonicalBillingProtocol.receipts.map { $0.request.url!.path } == ["/ouros/v1/fleet-console/offers"])
        #expect(CanonicalBillingProtocol.receipts.first?.request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(!client.available)
        #expect(opened.isEmpty)
    }
}
