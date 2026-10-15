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

private enum OurosKeychain {
    static let service = "com.fleetconsole.ouros"
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "account-session"]
    }
    private static func requireProductionContext() throws {
        guard OurosCredentialContext.current.permitsProductionStorage else {
            throw OurosCredentialStorageError.developmentRequiresExplicitStore
        }
        // Release app identity is verified without querying an account item.
        // An ad-hoc/development app cannot provoke a Keychain permission dialog.
        var code: SecCode?
        var requirement: SecRequirement?
        let rule = #"identifier "com.fleetconsole.app" and anchor apple generic and certificate leaf[subject.OU] = "47R2YVAFA2""#
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              let requirement, SecCodeCheckValidity(code, [], requirement) == errSecSuccess else {
            throw OurosCredentialStorageError.unavailable
        }
    }
    static func read() throws -> OurosCredential? {
        try requireProductionContext()
        var q = query
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw OurosCredentialStorageError.unavailable
        }
        return try JSONDecoder().decode(OurosCredential.self, from: data)
    }
    static func save(_ credential: OurosCredential) throws {
        try requireProductionContext()
        let data = try JSONEncoder().encode(credential)
        let status = SecItemUpdate(query as CFDictionary,
                                  [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw Failure.storage }
        } else if status != errSecSuccess { throw Failure.storage }
    }
    static func clear() throws {
        try requireProductionContext()
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OurosCredentialStorageError.unavailable
        }
    }
}

@MainActor
private struct ProductionOurosCredentialStore: OurosCredentialStore {
    func read() throws -> OurosCredential? { try OurosKeychain.read() }
    func save(_ credential: OurosCredential) throws { try OurosKeychain.save(credential) }
    func clear() throws { try OurosKeychain.clear() }
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
    case unavailable, signIn, invalidResponse, storage, server(String), gatewayRejected(Int, String)
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
    @ObservationIgnored private let credentialStore: any OurosCredentialStore
    private(set) var credentialStorageIssue: String?
    @ObservationIgnored private let operationDefaults: UserDefaults
    @ObservationIgnored private let openBrowser: (URL) -> Void
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var checkoutKey: String?
    private(set) var unconfirmedInvestigationID: String?
    private static let pendingInvestigationKey = "fleetconsole.investigation.unconfirmed.v1"

    init(credentialStore: (any OurosCredentialStore)? = nil, sessionConfiguration: URLSessionConfiguration = .ephemeral,
         operationDefaults: UserDefaults = .standard, openBrowser: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        let store = credentialStore ?? GuardedOurosCredentialStore(context: .current,
            makeBackend: { ProductionOurosCredentialStore() })
        self.credentialStore = store
        self.operationDefaults = operationDefaults
        unconfirmedInvestigationID = operationDefaults.string(forKey: Self.pendingInvestigationKey)
        self.sessionConfiguration = sessionConfiguration
        self.openBrowser = openBrowser
        do { credential = try store.read() }
        catch {
            credential = nil
            credentialStorageIssue = error.localizedDescription
            message = credentialStorageIssue
        }
    }

    var signedIn: Bool { credential.map { $0.expires > Date() } ?? false }
    var active: Bool {
        signedIn && membership?.active == true
            && (membership?.periodEnd.map { $0 > Date().timeIntervalSince1970 } ?? false)
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET",
                                      body: [String: String]? = nil, authenticated: Bool = true,
                                      operationKey: String? = nil, encodedBody: Data? = nil,
                                      timeout: TimeInterval = 20, classifyGatewayRefusal: Bool = false) async throws -> T {
        if let credentialStorageIssue { throw InvestigationGatewayError.refused(credentialStorageIssue) }
        let url = URL(string: "https://ouros.md" + path)!
        var request = URLRequest(url: url)
        request.httpMethod = method; request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard signedIn, let credential else { throw Failure.signIn }
            request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let encodedBody {
            request.httpBody = encodedBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let operationKey { request.setValue(operationKey, forHTTPHeaderField: "Idempotency-Key") }
        guard let configuration = sessionConfiguration.copy() as? URLSessionConfiguration else {
            throw Failure.invalidResponse
        }
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: OurosNoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.host == "ouros.md" else { throw Failure.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 65_536 else { throw Failure.invalidResponse }
            data.append(byte)
        }
        guard (200..<300).contains(http.statusCode) else {
            if classifyGatewayRefusal, InvestigationGatewayPayload.refusedBeforeDispatch(data: data, status: http.statusCode) {
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let nested = object?["error"] as? [String: Any]
                throw Failure.gatewayRejected(http.statusCode, object?["code"] as? String ?? nested?["code"] as? String ?? "request_refused")
            }
            let rejection = try? JSONDecoder().decode(OurosRejection.self, from: data)
            if http.statusCode == 401 { throw Failure.signIn }
            throw Failure.server(rejection?.code ?? rejection?.error ?? "unavailable")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// The existing Ouros Agent gateway rechecks account entitlement and reserves
    /// usage on POST. Fleet's multi-device membership does not authorize inference.
    func investigate(starter: String, validateObservation: @MainActor () -> Bool) async throws -> String {
        if let issue = credentialStorageIssue { throw InvestigationGatewayError.refused(issue) }
        guard signedIn, let accountSession = credential?.token else {
            throw InvestigationGatewayError.refused("Connect your Ouros account to investigate.")
        }
        guard !busy else { throw InvestigationGatewayError.refused("The account is busy. Try again when it finishes.") }
        if let outstanding = unconfirmedInvestigationID { throw InvestigationGatewayError.uncertain(outstanding) }
        busy = true
        defer { busy = false }
        struct Model: Decodable { let id: String }
        struct Catalog: Decodable {
            let ok: Bool
            let runnable: Bool
            let code: String?
            let defaultModelId: String?
            let models: [Model]
        }
        let catalog: Catalog
        do { catalog = try await request("/ouros/v1/models") }
        catch Failure.signIn {
            handle(Failure.signIn)
            throw InvestigationGatewayError.refused("The Ouros account session is no longer valid. Connect again; no analysis request was sent.")
        }
        catch { throw InvestigationGatewayError.refused("Ouros could not verify investigation availability. No analysis request was sent.") }
        guard catalog.ok, catalog.runnable,
              let model = catalog.models.first(where: { $0.id == catalog.defaultModelId }) ?? catalog.models.first else {
            throw InvestigationGatewayError.refused("The Ouros gateway has not authorized a runnable agent model for this account. A Fleet multi-device subscription does not grant agent access.")
        }
        guard signedIn, credential?.token == accountSession else {
            throw InvestigationGatewayError.refused("The connected account changed. Select the observation again.")
        }
        guard validateObservation() else {
            throw InvestigationGatewayError.refused("The selected observation became stale or its process changed while verifying access. Select it again.")
        }
        let payload = try InvestigationGatewayPayload.make(model: model.id, starter: starter)
        let operationID = UUID().uuidString
        // Persist before dispatch. Never retry an ambiguous paid operation, even after relaunch.
        unconfirmedInvestigationID = operationID
        operationDefaults.set(operationID, forKey: Self.pendingInvestigationKey)
        guard operationDefaults.synchronize() else {
            clearUnconfirmedInvestigation()
            throw InvestigationGatewayError.refused("The request identity could not be saved before dispatch. No analysis request was sent.")
        }
        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        do {
            let completion: Completion = try await request("/v1/chat/completions", method: "POST",
                operationKey: operationID, encodedBody: payload, timeout: 125, classifyGatewayRefusal: true)
            guard let reply = completion.choices.first?.message.content, !reply.isEmpty, reply.utf8.count <= 32_768 else {
                throw Failure.invalidResponse
            }
            clearUnconfirmedInvestigation()
            return reply
        } catch Failure.gatewayRejected(let status, let code) {
            clearUnconfirmedInvestigation()
            if status == 401 { handle(Failure.signIn) }
            throw InvestigationGatewayError.refused("The Ouros gateway refused this investigation: " + InvestigationRequest.label(code) + ". No local agent was started.")
        } catch {
            // Failure after dispatch may already have incurred usage. No blind replay.
            throw InvestigationGatewayError.uncertain(operationID)
        }
    }

    /// Explicit acknowledgement only; never resends the old request.
    func acknowledgeUnconfirmedInvestigation() {
        guard !busy else { return }
        clearUnconfirmedInvestigation()
    }

    private func clearUnconfirmedInvestigation() {
        unconfirmedInvestigationID = nil
        operationDefaults.removeObject(forKey: Self.pendingInvestigationKey)
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
        offers = catalog.configured ? catalog.offers : []
        available = catalog.configured && catalog.offers.contains(where: \.matchesMultiDevice)
    }

    @discardableResult func connect() -> Task<Void, Never>? {
        guard credentialStorageIssue == nil else { message = credentialStorageIssue; return nil }
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
                        try credentialStore.save(value)
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
            let value: Checkout = try await request("/hvy/v1/fleet-console/checkout", method: "POST",
                body: ["offerId": offerID], operationKey: operationKey)
            if let raw = value.url {
                guard let url = URL(string: raw), url.scheme == "https", url.host == "checkout.stripe.com",
                      url.user == nil, url.password == nil else { throw Failure.invalidResponse }
                NSWorkspace.shared.open(url); message = "Finish checkout, then refresh your subscription."
            } else if value.state == "expired" {
                if multiDevice { checkoutKey = nil }
                UserDefaults.standard.removeObject(forKey: keyName)
                message = "Checkout expired. Subscribe again to start a new checkout."
            } else if multiDevice {
                membership = try await request("/hvy/v1/fleet-console/entitlement")
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
        try? credentialStore.clear()
    }

    private func handle(_ error: Error) {
        if case Failure.signIn = error {
            membership = nil; credential = nil
            try? credentialStore.clear()
            message = "Connect your Ouros account to continue."
        } else if case Failure.server("access_denied") = error { message = "Account connection was denied. Connect again when you are ready." }
        else if case Failure.server("expired_token") = error { message = "Connection expired. Connect to Ouros again." }
        else if case Failure.server("checkout_expired") = error { message = "Checkout could not be recovered. Review your Ouros billing before starting another purchase." }
        else if case Failure.storage = error { message = "Your account could not be saved securely. Try again." }
        else if case Failure.server("already_subscribed") = error { message = "You already have multi-device access. Refresh your subscription." }
        else { message = "Ouros could not complete the request. Try again." }
    }
}
