import Foundation
import Testing
@testable import FleetConsoleApp

@Suite(.serialized)
struct OurosCredentialIsolationTests {
    private func context(debug: Bool = false, process: String = "FleetConsole", bundle: String? = "com.fleetconsole.app",
                         executable: String? = "FleetConsole", application: Bool = true, signature: Bool = true,
                         environment: Bool = false, arguments: Bool = false) -> OurosCredentialContext {
        .init(debugBuild: debug, processName: process, bundleID: bundle, executableName: executable,
              isApplicationBundle: application, sealedSignaturePresent: signature,
              harnessEnvironment: environment, harnessArguments: arguments)
    }

    @MainActor @Test func deniedContextsCannotEvenInitializeTheBackend() throws {
        let denied = [context(debug: true), context(process: "swift-frontend"), context(process: "swift"),
                      context(process: "xctest"), context(bundle: nil), context(application: false),
                      context(signature: false), context(environment: true), context(arguments: true)]
        for current in denied {
            var factories = 0
            let fake = TestOurosCredentialStore()
            let guarded = GuardedOurosCredentialStore(context: current, makeBackend: { factories += 1; return fake })
            #expect(throws: OurosCredentialStorageError.self) { try guarded.read() }
            #expect(throws: OurosCredentialStorageError.self) {
                try guarded.save(.init(token: "synthetic-only", expires: .distantFuture))
            }
            #expect(throws: OurosCredentialStorageError.self) { try guarded.clear() }
            #expect(factories == 0)
            #expect(fake.reads == 0 && fake.saves == 0 && fake.clears == 0)
        }
    }

    @MainActor @Test func permittedContextUsesOnlyItsExplicitBackend() throws {
        let fake = TestOurosCredentialStore()
        var factories = 0
        let guarded = GuardedOurosCredentialStore(context: context(), makeBackend: { factories += 1; return fake })
        #expect(try guarded.read() == nil)
        try guarded.save(.init(token: "synthetic-only", expires: .distantFuture))
        try guarded.clear()
        #expect(factories == 3)
        #expect(fake.reads == 1 && fake.saves == 1 && fake.clears == 1)
    }

    @MainActor @Test func missingTestInjectionFailsLocally() async {
        #expect(!OurosCredentialContext.current.permitsProductionStorage)
        var browserCalls = 0
        let configuration = URLSessionConfiguration.ephemeral
        // No credentials or URLProtocol are needed: a denied storage context
        // must fail before constructing a network request or browser action.
        let billing = OurosBilling(sessionConfiguration: configuration, openBrowser: { _ in browserCalls += 1 })
        #expect(billing.credentialStorageIssue != nil)
        #expect(!billing.signedIn)
        #expect(billing.connect() == nil)
        #expect(browserCalls == 0)
        do {
            _ = try await billing.investigate(starter: "synthetic-only", validateObservation: { true })
            Issue.record("Missing injection must refuse locally")
        } catch { #expect(error is InvestigationGatewayError) }
    }
}
