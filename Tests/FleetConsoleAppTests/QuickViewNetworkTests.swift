import Foundation
import FleetCore
import Testing
@testable import FleetConsoleApp

struct QuickViewNetworkTests {
    @Test func rateBarsHaveAStableScaleAndPreserveIdleVersusUnknown() {
        #expect(QuickViewRate(bytesPerSecond: nil).fraction == nil)
        #expect(QuickViewRate(bytesPerSecond: -1).fraction == nil)
        #expect(QuickViewRate(bytesPerSecond: .nan).fraction == nil)
        #expect(QuickViewRate(bytesPerSecond: .infinity).fraction == nil)
        #expect(QuickViewRate(bytesPerSecond: 0).fraction == 0)
        #expect(QuickViewRate(bytesPerSecond: 1_000_000_000).fraction == 1)
        #expect(QuickViewRate(bytesPerSecond: 2_000_000_000).fraction == 1)
        #expect(QuickViewRate(bytesPerSecond: 10_000).fraction! < QuickViewRate(bytesPerSecond: 100_000).fraction!)
        #expect(QuickViewRate(bytesPerSecond: nil).readout == "—")
        #expect(QuickViewRate(bytesPerSecond: 0).readout != "—")
    }
}
