import SwiftUI

enum FleetCorePalette {
    static var signal: Color { color(OurosCoreTokens.brandSignalHex) }
    static var actionBackground: Color { color(OurosCoreTokens.actionBackgroundHex) }
    static var actionForeground: Color { color(OurosCoreTokens.actionForegroundHex) }

    private static func color(_ packed: UInt32) -> Color {
        Color(.sRGB,
              red: Double((packed >> 16) & 255) / 255,
              green: Double((packed >> 8) & 255) / 255,
              blue: Double(packed & 255) / 255,
              opacity: 1)
    }
}

extension View {
    func fleetPrimaryAction() -> some View {
        buttonStyle(.borderedProminent)
            .tint(FleetCorePalette.actionBackground)
            .foregroundStyle(FleetCorePalette.actionForeground)
    }
}
