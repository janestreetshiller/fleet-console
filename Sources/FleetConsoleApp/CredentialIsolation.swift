import Foundation

struct OurosCredential: Codable, Sendable, Equatable {
    let token: String
    let expires: Date
}

enum OurosCredentialStorageError: LocalizedError {
    case developmentRequiresExplicitStore, unavailable
    var errorDescription: String? {
        switch self {
        case .developmentRequiresExplicitStore:
            return "Account storage is disabled in development/test harnesses. Inject a fake credential store; no Keychain access or account connection was attempted."
        case .unavailable: return "The account credential store is unavailable."
        }
    }
}

/// Pure context checks precede any Security.framework entry. Debug builds,
/// interpreters, test runners and unbundled tools cannot select real storage.
struct OurosCredentialContext: Sendable {
    let debugBuild: Bool
    let processName: String
    let bundleID: String?
    let executableName: String?
    let isApplicationBundle: Bool
    let sealedSignaturePresent: Bool
    let harnessEnvironment: Bool
    let harnessArguments: Bool

    var permitsProductionStorage: Bool {
        !debugBuild && !harnessEnvironment && !harnessArguments
            && processName == "FleetConsole" && executableName == "FleetConsole"
            && bundleID == "com.fleetconsole.app" && isApplicationBundle && sealedSignaturePresent
    }

    static var current: Self {
        #if DEBUG
        let debugBuild = true
        #else
        let debugBuild = false
        #endif
        let environment = ProcessInfo.processInfo.environment
        let harnessKeys = ["XCTestConfigurationFilePath", "XCTestSessionIdentifier", "SWIFT_TESTING_ENABLED",
                           "SWIFT_TESTING_LIBRARY", "FLEET_DEVELOPMENT_CHECK", "FLEET_TEST_HARNESS"]
        let arguments = ProcessInfo.processInfo.arguments
        let bundle = Bundle.main
        return Self(debugBuild: debugBuild, processName: ProcessInfo.processInfo.processName,
                    bundleID: bundle.bundleIdentifier, executableName: bundle.executableURL?.lastPathComponent,
                    isApplicationBundle: bundle.bundleURL.pathExtension == "app"
                        && bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
                    sealedSignaturePresent: FileManager.default.fileExists(atPath:
                        bundle.bundleURL.appendingPathComponent("Contents/_CodeSignature/CodeResources").path),
                    harnessEnvironment: harnessKeys.contains { environment[$0] != nil },
                    harnessArguments: arguments.contains { $0 == "-interpret" || $0 == "--testing-library"
                        || $0 == "--test" || $0.hasSuffix(".xctest") })
    }
}

@MainActor
protocol OurosCredentialStore {
    func read() throws -> OurosCredential?
    func save(_ credential: OurosCredential) throws
    func clear() throws
}

/// Missing test injection fails locally. There is deliberately no fallback.
@MainActor
struct UnavailableOurosCredentialStore: OurosCredentialStore {
    func read() throws -> OurosCredential? { throw OurosCredentialStorageError.developmentRequiresExplicitStore }
    func save(_ credential: OurosCredential) throws { throw OurosCredentialStorageError.developmentRequiresExplicitStore }
    func clear() throws { throw OurosCredentialStorageError.developmentRequiresExplicitStore }
}

/// The backend is a lazy factory: a denied context cannot initialize production
/// storage or a singleton as a side effect of deciding whether it is allowed.
@MainActor
struct GuardedOurosCredentialStore: OurosCredentialStore {
    let context: OurosCredentialContext
    let makeBackend: @MainActor () -> any OurosCredentialStore

    private func backend() throws -> any OurosCredentialStore {
        guard context.permitsProductionStorage else {
            throw OurosCredentialStorageError.developmentRequiresExplicitStore
        }
        return makeBackend()
    }
    func read() throws -> OurosCredential? { try backend().read() }
    func save(_ credential: OurosCredential) throws { try backend().save(credential) }
    func clear() throws { try backend().clear() }
}
