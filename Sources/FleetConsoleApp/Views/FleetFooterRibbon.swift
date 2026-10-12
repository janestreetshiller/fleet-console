import SwiftUI
import FleetCore

/// Shared menu and dashboard action strip. Keep its size independent of content.
struct FleetFooterRibbon<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            content
                .padding(.horizontal, FleetMetrics.gutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: DashboardContentGeometry.footerHeight)
        .background(.bar)
    }
}
