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

private struct FleetPrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: ConsoleMetrics.controlCorner, style: .continuous)
        let shade = !isEnabled ? 0.20 : configuration.isPressed ? 0.12 : hovering ? 0.06 : 0
        return configuration.label
            .font(controlSize == .small || controlSize == .mini ? FleetFont.micro : FleetFont.body)
            .foregroundStyle(FleetCorePalette.actionForeground)
            .padding(.horizontal, controlSize == .small || controlSize == .mini ? 10 : 12)
            .padding(.vertical, controlSize == .mini ? 2 : 4)
            .background {
                shape.fill(FleetCorePalette.actionBackground)
                    .overlay { shape.fill(Color.black.opacity(shade)) }
            }
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : FleetAnimation.disclosure, value: configuration.isPressed)
    }
}

extension View {
    func fleetPrimaryAction() -> some View {
        buttonStyle(FleetPrimaryActionStyle())
    }
}
