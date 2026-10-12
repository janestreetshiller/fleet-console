import AppKit
import SwiftUI
import Testing
@testable import FleetConsoleApp

struct FooterRibbonTests {
    @MainActor @Test func menuAndDashboardRibbonShareOneHeight() {
        let host = NSHostingView(rootView: FleetFooterRibbon { Text("Actions") })
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 100)
        #expect(host.fittingSize.height == 44)
    }
}
