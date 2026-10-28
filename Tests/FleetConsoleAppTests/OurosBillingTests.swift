import Foundation
import Testing
@testable import FleetConsoleApp

struct OurosBillingTests {
    @Test func multiDeviceTermsRequireTheExactAuthorizedPrice() throws {
        func terms(_ cents: Int, _ currency: String = "usd", _ interval: String = "month", _ count: Int = 1) throws -> OurosOffer {
            let data = try JSONSerialization.data(withJSONObject: ["id": "fleet-console-multi-device", "priceCents": cents,
                "currency": currency, "interval": interval, "intervalCount": count])
            return try JSONDecoder().decode(OurosOffer.self, from: data)
        }
        #expect(try terms(1000).matchesMultiDevice)
        #expect(try !terms(1900).matchesMultiDevice)
        #expect(try !terms(1000, "eur").matchesMultiDevice)
        #expect(try !terms(1000, "usd", "year").matchesMultiDevice)
        #expect(try !terms(1000, "usd", "month", 2).matchesMultiDevice)
    }
}
