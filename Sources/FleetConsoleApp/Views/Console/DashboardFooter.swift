import SwiftUI
import FleetCore

/// One quiet underside for every dashboard destination, including a tucked sidebar.
struct DashboardFooter: View {
    @Bindable var model: AppModel

    var body: some View {
        FleetFooterRibbon {
            HStack(spacing: 8) {
                StatusPip(tone: model.connected ? .good : .bad, size: 7)
                Text(model.connected ? "Controller connected" : "Controller offline")
                    .font(ConsoleFont.caption).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button { model.openURL("https://ouros.md") } label: {
                    HStack(spacing: 4) {
                        Text("Ouros")
                        Image(systemName: "arrow.up.right").font(FleetFont.marker)
                    }
                    .font(FleetFont.subtitle).foregroundStyle(.secondary)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Visit the Ouros website")
                IconButton(symbol: "chevron.left.forwardslash.chevron.right", help: "FleetConsole source and support") {
                    model.openURL("https://github.com/janestreetshiller/fleet-console")
                }
            }
        }
    }
}
