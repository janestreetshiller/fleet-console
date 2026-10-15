import Foundation
@testable import FleetConsoleApp

@MainActor
final class TestOurosCredentialStore: OurosCredentialStore {
    var credential: OurosCredential?
    private(set) var reads = 0
    private(set) var saves = 0
    private(set) var clears = 0
    init(_ credential: OurosCredential? = nil) { self.credential = credential }
    func read() throws -> OurosCredential? { reads += 1; return credential }
    func save(_ value: OurosCredential) throws { saves += 1; credential = value }
    func clear() throws { clears += 1; credential = nil }
}
