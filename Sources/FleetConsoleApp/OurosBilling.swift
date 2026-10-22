import Foundation
import AppKit
import Security
import Observation

struct OurosOffer: Decodable, Sendable {
    let id: String
    let priceCents: Int
    let currency: String
    let interval: String
    let intervalCount: Int
    var matchesMultiDevice: Bool {
        id == "fleet-console-multi-device" && priceCents == 1000 && currency == "usd"
            && interval == "month" && intervalCount == 1
    }

    /// The hosted fixer. Its price comes from the catalog, never from here.
    static let cloudAgentID = "fleet-console-cloud-agent"

    /// "$10/month", from the catalog's own figures.
    var priceLabel: String {
        let amount = (Decimal(priceCents) / 100).formatted(.currency(code: currency.uppercased())
            .precision(.fractionLength(priceCents % 100 == 0 ? 0 : 2)))
        return intervalCount == 1 ? "\(amount)/\(interval)" : "\(amount) every \(intervalCount) \(interval)s"
    }
}

struct OurosMembership: Decodable, Sendable {
    let accountID: String
    let active: Bool
    let periodEnd: TimeInterval?
    let cancelAtPeriodEnd: Bool?
}

private struct OurosCredential: Codable {
    let token: String
    let expires: Date
}

private enum OurosKeychain {
    static let service = "com.fleetconsole.ouros"
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "account-session"]
    }
    static func read() -> OurosCredential? {
        var q = query
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(OurosCredential.self, from: data)
    }
    static func save(_ credential: OurosCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let status = SecItemUpdate(query as CFDictionary,
                                  [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw OurosFailure.storage }
        } else if status != errSecSuccess { throw OurosFailure.storage }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}

private struct OurosRejection: Decodable { var code: String?; var error: String? }

private final class OurosNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum OurosFailure: Error {
    case unavailable, signIn, invalidResponse, storage, server(String)
}

@Observable @MainActor
final class OurosBilling {
    private(set) var available = false
    /// The catalog as last loaded; empty until a load succeeds.
    private(set) var offers: [OurosOffer] = []
    private(set) var membership: OurosMembership?
    private(set) var busy = false
    private(set) var userCode: String?
    private(set) var verificationURL: URL?
    var message: String?
    @ObservationIgnored private var credential: OurosCredential?
    @ObservationIgnored private let sessionConfiguration: URLSessionConfiguration
    @ObservationIgnored private let useKeychain: Bool
    @ObservationIgnored private let openBrowser: (URL) -> Void
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var checkoutKey: String?

    init(useKeychain: Bool = true, sessionConfiguration: URLSessionConfiguration = .ephemeral,
         openBrowser: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        credential = useKeychain ? OurosKeychain.read() : nil
        self.useKeychain = useKeychain
        self.sessionConfiguration = sessionConfiguration
        self.openBrowser = openBrowser
    }

    var signedIn: Bool { credential.map { $0.expires > Date() } ?? false }
    var active: Bool {
        signedIn && membership?.active == true
            && (membership?.periodEnd.map { $0 > Date().timeIntervalSince1970 } ?? false)
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET",
                                      body: [String: String]? = nil, authenticated: Bool = true,
                                      operationKey: String? = nil) async throws -> T {
        let data = try await dataRequest(path, method: method,
            body: body.map { try JSONEncoder().encode($0) }, authenticated: authenticated,
            operationKey: operationKey, timeout: 20, responseLimit: 65_536)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func agentRequest(_ path: String, method: String = "GET", body: Data? = nil,
                      operationKey: String? = nil) async throws -> Data {
        guard ["/ouros/v1/models", "/v1/chat/completions", "/hvy/v1/billing/credits"].contains(path) else {
            throw OurosFailure.invalidResponse
        }
        if path == "/v1/chat/completions" {
            guard method == "POST", let body, body.count <= 16_384, let operationKey,
                  operationKey.range(of: "^[A-Za-z0-9_-]{16,128}$", options: .regularExpression) != nil else {
                throw OurosFailure.invalidResponse
            }
        } else if method != "GET" || body != nil { throw OurosFailure.invalidResponse }
        return try await dataRequest(path, method: method, body: body,
            operationKey: operationKey, timeout: 125, responseLimit: 1_048_576)
    }

    private func dataRequest(_ path: String, method: String, body: Data?,
                             authenticated: Bool = true, operationKey: String?,
                             timeout: TimeInterval, responseLimit: Int) async throws -> Data {
        let url = URL(string: "https://ouros.md" + path)!
        var request = URLRequest(url: url)
        request.httpMethod = method; request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard signedIn, let credential else { throw OurosFailure.signIn }
            request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let operationKey { request.setValue(operationKey, forHTTPHeaderField: "Idempotency-Key") }
        guard let configuration = sessionConfiguration.copy() as? URLSessionConfiguration else {
            throw OurosFailure.invalidResponse
        }
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: OurosNoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.host == "ouros.md",
              data.count <= responseLimit else { throw OurosFailure.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { handle(OurosFailure.signIn); throw OurosFailure.signIn }
            let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let nested = value?["error"] as? [String: Any]
            let code = value?["code"] as? String
                ?? value?["error"] as? String
                ?? nested?["code"] as? String
                ?? nested?["message"] as? String
                ?? "unavailable"
            throw OurosFailure.server(code)
        }
        return data
    }

    /// Automatic refresh follows an account connection; unsigned-in requests
    /// require an explicit billing action such as Refresh.
    func refresh(userInitiated: Bool = false) async {
        guard !busy, userInitiated || signedIn else { return }
        busy = true; defer { busy = false }
        do {
            try await loadOffers()
            if signedIn {
                membership = try await request("/ouros/v1/fleet-console/entitlement")
                if active { checkoutKey = nil }
            } else { membership = nil }
            if !available {
                message = "Ouros billing is unavailable. Try again."
            } else if !signedIn && userInitiated {
                message = "Sign in to check your subscription. If you already paid, use the same Ouros account."
            } else {
                message = nil
            }
        } catch { handle(error) }
    }

    private func loadOffers() async throws {
        struct Catalog: Decodable { let configured: Bool; let offers: [OurosOffer] }
        let catalog: Catalog = try await request("/ouros/v1/fleet-console/offers", authenticated: false)
        offers = catalog.configured ? catalog.offers : []
        available = catalog.configured && catalog.offers.contains(where: \.matchesMultiDevice)
    }

    @discardableResult func connect() -> Task<Void, Never>? {
        guard !busy else { return nil }
        connectionTask?.cancel()
        connectionTask = Task {
            busy = true
            defer { busy = false; userCode = nil; verificationURL = nil }
            do {
                struct Grant: Decodable {
                    let device_code: String; let user_code: String
                    let verification_uri_complete: String; let expires_in: Int; let interval: Int
                }
                let grant: Grant = try await request("/auth/device/code", method: "POST",
                                                     body: ["client_id": "ouros-desktop"], authenticated: false)
                guard grant.expires_in > 0, grant.expires_in <= 600,
                      grant.interval >= 5, grant.interval <= 60,
                      grant.user_code.range(of: "^[A-Z2-9]{4}-[A-Z2-9]{4}$", options: .regularExpression) != nil,
                      let url = URL(string: grant.verification_uri_complete), url.scheme == "https",
                      url.host == "ouros.md", url.path == "/auth/device/verify",
                      url.user == nil, url.password == nil else { throw OurosFailure.invalidResponse }
                userCode = grant.user_code; verificationURL = url; message = nil
                openBrowser(url)
                let deadline = Date().addingTimeInterval(Double(grant.expires_in))
                var interval = grant.interval
                while Date() < deadline {
                    try await Task.sleep(for: .seconds(interval))
                    try Task.checkCancellation()
                    do {
                        struct Token: Decodable { let access_token: String; let token_type: String; let expires_in: Int }
                        let token: Token = try await request("/auth/device/token", method: "POST",
                            body: ["client_id": "ouros-desktop", "device_code": grant.device_code,
                                   "grant_type": "urn:ietf:params:oauth:grant-type:device_code"], authenticated: false)
                        guard token.token_type == "Bearer", token.expires_in > 0,
                              token.access_token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { throw OurosFailure.invalidResponse }
                        let value = OurosCredential(token: token.access_token,
                                                    expires: Date().addingTimeInterval(Double(token.expires_in)))
                        if useKeychain { try OurosKeychain.save(value) }
                        credential = value
                        membership = try await request("/ouros/v1/fleet-console/entitlement")
                        try await loadOffers()
                        message = available ? nil : "Ouros billing is unavailable. Try again."
                        return
                    } catch OurosFailure.server("authorization_pending") { continue }
                    catch OurosFailure.server("slow_down") { interval = min(60, interval + 5) }
                }
                message = "Connection expired. Connect to Ouros again."
            } catch is CancellationError { message = nil }
            catch { handle(error) }
        }
        return connectionTask
    }

    func cancelConnection() { connectionTask?.cancel(); connectionTask = nil }

    /// The cloud agent, when the catalog offers it to this account.
    var cloudAgentOffer: OurosOffer? { offers.first { $0.id == OurosOffer.cloudAgentID } }

    func subscribe() async {
        guard available else { return }
        await subscribe(offerID: "fleet-console-multi-device")
    }

    /// Checkout for one catalog offer. Each offer keeps its own idempotency key,
    /// so starting a second purchase can never resume the first one's session.
    func subscribe(offerID: String) async {
        guard signedIn, !busy, offers.contains(where: { $0.id == offerID }) else { return }
        busy = true; defer { busy = false }
        do {
            let multiDevice = offerID == "fleet-console-multi-device"
            let keyName = multiDevice
                ? "fleetconsole.ouros.checkout.\(membership?.accountID ?? "")"
                : "fleetconsole.ouros.checkout.\(offerID).\(membership?.accountID ?? "")"
            // The in-memory key belongs to the multi-device checkout alone; any
            // other offer reads and writes only its own stored key.
            let operationKey = (multiDevice ? checkoutKey : nil)
                ?? UserDefaults.standard.string(forKey: keyName) ?? UUID().uuidString
            if multiDevice { checkoutKey = operationKey }
            UserDefaults.standard.set(operationKey, forKey: keyName)
            struct Checkout: Decodable { var url: String?; var state: String? }
            let value: Checkout = try await request("/ouros/v1/fleet-console/checkout", method: "POST",
                body: ["offerId": offerID], operationKey: operationKey)
            if let raw = value.url {
                guard let url = URL(string: raw), url.scheme == "https", url.host == "checkout.stripe.com",
                      url.user == nil, url.password == nil else { throw OurosFailure.invalidResponse }
                openBrowser(url); message = "Finish checkout, then refresh your subscription."
            } else if value.state == "expired" {
                if multiDevice { checkoutKey = nil }
                UserDefaults.standard.removeObject(forKey: keyName)
                message = "Checkout expired. Subscribe again to start a new checkout."
            } else if multiDevice {
                membership = try await request("/ouros/v1/fleet-console/entitlement")
                message = active ? nil : "Payment is not confirmed. Refresh your subscription."
            } else {
                message = "Checkout is complete. The cloud agent appears once Ouros confirms payment."
            }
        } catch { handle(error) }
    }

    func manage() async {
        guard signedIn, !busy else { return }
        busy = true; defer { busy = false }
        do {
            struct Portal: Decodable { let url: String }
            let value: Portal = try await request("/ouros/v1/fleet-console/portal", method: "POST", body: [:])
            guard let url = URL(string: value.url), url.scheme == "https", url.host == "billing.stripe.com",
                  url.user == nil, url.password == nil else { throw OurosFailure.invalidResponse }
            openBrowser(url)
        } catch { handle(error) }
    }

    func disconnect() async {
        guard !busy else { return }
        cancelConnection(); busy = true
        defer { busy = false }
        do {
            struct Result: Decodable { let ok: Bool }
            let _: Result = try await request("/auth/logout", method: "POST", body: [:])
            message = nil
        } catch { message = "Account disconnected from this Mac. Ouros could not confirm server sign-out." }
        credential = nil; membership = nil; checkoutKey = nil
        if useKeychain { OurosKeychain.clear() }
    }

    private func handle(_ error: Error) {
        if case OurosFailure.signIn = error {
            membership = nil; credential = nil
            if useKeychain { OurosKeychain.clear() }
            message = "Connect your Ouros account to continue."
        } else if case OurosFailure.server("access_denied") = error { message = "Account connection was denied. Connect again when you are ready." }
        else if case OurosFailure.server("expired_token") = error { message = "Connection expired. Connect to Ouros again." }
        else if case OurosFailure.server("checkout_expired") = error { message = "Checkout could not be recovered. Review your Ouros billing before starting another purchase." }
        else if case OurosFailure.storage = error { message = "Your account could not be saved securely. Try again." }
        else if case OurosFailure.server("already_subscribed") = error { message = "You already have multi-device access. Refresh your subscription." }
        else { message = "Ouros could not complete the request. Try again." }
    }
}
