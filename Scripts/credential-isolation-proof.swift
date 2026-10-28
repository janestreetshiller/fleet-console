import Foundation

@MainActor
final class FakeProofStore: OurosCredentialStore {
    var reads = 0
    var saves = 0
    var clears = 0
    func read() throws -> OurosCredential? { reads += 1; return nil }
    func save(_ credential: OurosCredential) throws { saves += 1 }
    func clear() throws { clears += 1 }
}

@main
struct CredentialIsolationProof {
    @MainActor static func main() throws {
        func context(debug: Bool = false, process: String = "FleetConsole", bundle: String? = "com.fleetconsole.app",
                     app: Bool = true, signature: Bool = true, environment: Bool = false,
                     arguments: Bool = false) -> OurosCredentialContext {
            .init(debugBuild: debug, processName: process, bundleID: bundle, executableName: "FleetConsole",
                  isApplicationBundle: app, sealedSignaturePresent: signature,
                  harnessEnvironment: environment, harnessArguments: arguments)
        }
        let denied = [context(debug: true), context(process: "swift-frontend"), context(process: "swift"),
                      context(process: "xctest"), context(bundle: nil), context(app: false),
                      context(signature: false), context(environment: true), context(arguments: true), .current]
        var blocked = 0
        var deniedFactories = 0
        for value in denied {
            let guarded = GuardedOurosCredentialStore(context: value, makeBackend: {
                deniedFactories += 1
                return FakeProofStore()
            })
            let operations: [() throws -> Void] = [
                { _ = try guarded.read() },
                { try guarded.save(.init(token: "synthetic-only", expires: .distantFuture)) },
                { try guarded.clear() }
            ]
            for operation in operations {
                do { try operation(); fatalError("Denied context reached a credential operation") }
                catch OurosCredentialStorageError.developmentRequiresExplicitStore { blocked += 1 }
            }
        }
        precondition(deniedFactories == 0)
        let fake = FakeProofStore()
        let allowed = GuardedOurosCredentialStore(context: context(), makeBackend: { fake })
        _ = try allowed.read()
        try allowed.save(.init(token: "synthetic-only", expires: .distantFuture))
        try allowed.clear()
        precondition(fake.reads == 1 && fake.saves == 1 && fake.clears == 1)
        let result: [String: Any] = ["deniedContexts": denied.count, "blockedOperations": blocked,
            "deniedBackendInitializations": deniedFactories, "explicitFakeOperations": 3]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
