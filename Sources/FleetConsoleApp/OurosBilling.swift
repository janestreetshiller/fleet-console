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
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw Failure.storage }
        } else if status != errSecSuccess { throw Failure.storage }
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

private enum Failure: Error {
    case unavailable, signIn, invalidResponse, storage, server(String)
}

@Observable @MainActor
final class OurosBilling {
    private(set) var available = false
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
        let url = URL(string: "https://ouros.md" + path)!
        var request = URLRequest(url: url)
        request.httpMethod = method; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard signedIn, let credential else { throw Failure.signIn }
            request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let operationKey { request.setValue(operationKey, forHTTPHeaderField: "Idempotency-Key") }
        guard let configuration = sessionConfiguration.copy() as? URLSessionConfiguration else {
            throw Failure.invalidResponse
        }
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: OurosNoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.host == "ouros.md",
              data.count <= 65_536 else { throw Failure.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let rejection = try? JSONDecoder().decode(OurosRejection.self, from: data)
            if http.statusCode == 401 { throw Failure.signIn }
            throw Failure.server(rejection?.code ?? rejection?.error ?? "unavailable")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Automatic refresh follows an account connection; unsigned-in requests
    /// require an explicit billing action such as Refresh.
    func refresh(userInitiated: Bool = false) async {
        guard !busy, userInitiated || signedIn else { return }
        busy = true; defer { busy = false }
        do {
            try await loadOffers()
            if signedIn {
                membership = try await request("/hvy/v1/fleet-console/entitlement")
                if active { checkoutKey = nil }
            } else { membership = nil }
            message = available ? nil : "Ouros billing is unavailable. Try again."
        } catch { handle(error) }
    }

    private func loadOffers() async throws {
        struct Catalog: Decodable { let configured: Bool; let offers: [OurosOffer] }
        let catalog: Catalog = try await request("/hvy/v1/fleet-console/offers", authenticated: false)
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
                      url.user == nil, url.password == nil else { throw Failure.invalidResponse }
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
                              token.access_token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { throw Failure.invalidResponse }
                        let value = OurosCredential(token: token.access_token,
                                                    expires: Date().addingTimeInterval(Double(token.expires_in)))
                        if useKeychain { try OurosKeychain.save(value) }
                        credential = value
                        membership = try await request("/hvy/v1/fleet-console/entitlement")
                        try await loadOffers()
                        message = available ? nil : "Ouros billing is unavailable. Try again."
                        return
                    } catch Failure.server("authorization_pending") { continue }
                    catch Failure.server("slow_down") { interval = min(60, interval + 5) }
                }
                message = "Connection expired. Connect to Ouros again."
            } catch is CancellationError { message = nil }
            catch { handle(error) }
        }
        return connectionTask
    }

    func cancelConnection() { connectionTask?.cancel(); connectionTask = nil }

    func subscribe() async {
        guard signedIn, available, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let keyName = "fleetconsole.ouros.checkout.\(membership?.accountID ?? "")"
            checkoutKey = checkoutKey ?? UserDefaults.standard.string(forKey: keyName) ?? UUID().uuidString
            UserDefaults.standard.set(checkoutKey, forKey: keyName)
            struct Checkout: Decodable { var url: String?; var state: String? }
            let value: Checkout = try await request("/hvy/v1/fleet-console/checkout", method: "POST",
                body: ["offerId": "fleet-console-multi-device"], operationKey: checkoutKey)
            if let raw = value.url {
                guard let url = URL(string: raw), url.scheme == "https", url.host == "checkout.stripe.com",
                      url.user == nil, url.password == nil else { throw Failure.invalidResponse }
                NSWorkspace.shared.open(url); message = "Finish checkout, then refresh your subscription."
            } else if value.state == "expired" {
                checkoutKey = nil; UserDefaults.standard.removeObject(forKey: keyName)
                message = "Checkout expired. Subscribe again to start a new checkout."
            } else { membership = try await request("/hvy/v1/fleet-console/entitlement"); message = active ? nil : "Payment is not confirmed. Refresh your subscription." }
        } catch { handle(error) }
    }

    func manage() async {
        guard signedIn, !busy else { return }
        busy = true; defer { busy = false }
        do {
            struct Portal: Decodable { let url: String }
            let value: Portal = try await request("/hvy/v1/fleet-console/portal", method: "POST", body: [:])
            guard let url = URL(string: value.url), url.scheme == "https", url.host == "billing.stripe.com",
                  url.user == nil, url.password == nil else { throw Failure.invalidResponse }
            NSWorkspace.shared.open(url)
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
        if case Failure.signIn = error {
            membership = nil; credential = nil
            if useKeychain { OurosKeychain.clear() }
            message = "Connect your Ouros account to continue."
        } else if case Failure.server("access_denied") = error { message = "Account connection was denied. Connect again when you are ready." }
        else if case Failure.server("expired_token") = error { message = "Connection expired. Connect to Ouros again." }
        else if case Failure.server("checkout_expired") = error { message = "Checkout could not be recovered. Review your Ouros billing before starting another purchase." }
        else if case Failure.storage = error { message = "Your account could not be saved securely. Try again." }
        else if case Failure.server("already_subscribed") = error { message = "You already have multi-device access. Refresh your subscription." }
        else { message = "Ouros could not complete the request. Try again." }
    }
}
