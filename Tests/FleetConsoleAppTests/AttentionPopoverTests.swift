import Foundation
import Testing

struct AttentionPopoverTests {
    @Test("Services popover explains attention even when no service row exists")
    func attentionIsNotHiddenByServiceMembership() throws {
        // Guard the composition seam: the regression removed this existing
        // component while the model and status-item badge continued to work.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/FleetConsoleApp/Views/PopoverView.swift"), encoding: .utf8)
        let content = try #require(source.components(separatedBy: "// MARK: - Shared alerts").first)
        #expect(content.contains("if !model.attention.isEmpty"))
        #expect(content.contains("AttentionSection(model: model, expandedService: $expanded, openDashboard: openDashboard)"))
    }
}
