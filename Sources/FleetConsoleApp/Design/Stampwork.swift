import SwiftUI
import AppKit
import CoreText

// Stampwork — the textured/stamped treatment layer.
//
// A restrained pass of paper-and-ink over the console chrome:
//
//   * `PaperGrain` — a deterministic procedural grain (no image assets) drawn
//     once per size class into an Image and cached. Ink flecks at ~3% opacity,
//     so text on top keeps full contrast.
//   * `StampFont` — the bundled display face ("Special Elite", Apache-2.0,
//     vendored at Sources/FleetConsoleApp/Resources/FleetStamp.ttf), registered
//     from the bundle on first use. No network fetch, ever.
//   * `FleetMark` — the stamped logo mark: a letterpress-style plate holding
//     the brand glyph, slightly rotated like a hand-struck stamp.
//
// Everything here is achromatic except where it borrows `ConsoleColor`, and
// nothing here intercepts input: every overlay sets `allowsHitTesting(false)`.

// MARK: - Font

enum StampFont {
    /// The family name baked into the bundled TTF.
    static let family = "Special Elite"
    /// Letter-tracking that reads as handset type without hurting legibility.
    static let tracking: CGFloat = 1.2

    private static let registrationLock = NSLock()
    private nonisolated(unsafe) static var registered = false

    /// Registers the bundled font exactly once. Safe to call from any thread;
    /// CTFontManager registration is itself serialized, the lock only guards
    /// the flag.
    static func register() {
        registrationLock.lock()
        defer { registrationLock.unlock() }
        guard !registered else { return }
        registered = true
        guard let url = Bundle.module.url(forResource: "FleetStamp", withExtension: "ttf") else {
            assertionFailure("FleetStamp.ttf missing from bundle")
            return
        }
        guard let data = try? Data(contentsOf: url),
              let provider = CGDataProvider(data: data as CFData),
              let cgFont = CGFont(provider) else {
            assertionFailure("FleetStamp.ttf unreadable")
            return
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterGraphicsFont(cgFont, &error) {
            // Already registered is fine; anything else is a packaging bug.
            registered = (error == nil)
        }
    }

    /// The stamp face at `size`, never below 16pt — this face is used only for
    /// display text, so it holds the legibility floor everywhere it appears.
    static func display(_ size: CGFloat = 17) -> Font {
        register()
        return .custom(family, size: max(16, size))
    }
}

// MARK: - Paper grain

/// Deterministic paper/ink texture. Seeded LCG so the same surface always
/// renders identically across launches — no flicker between redraws.
struct PaperGrain: View {
    var seed: UInt64 = 0x5EED
    var opacity: Double = 0.035

    var body: some View {
        Canvas { context, size in
            // Grain is drawn at half resolution and scaled up: the flecks read
            // as paper fibre rather than pixel noise on Retina.
            let step: CGFloat = 3
            var state = seed &* 2862933555777941757 &+ 3037000493
            func next() -> Double {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
            }
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    if next() < 0.18 {
                        let grey = next()
                        let rect = CGRect(x: x, y: y, width: 1.2, height: 1.2)
                        context.fill(
                            Path(rect),
                            with: .color(Color(red: grey, green: grey, blue: grey)
                                .opacity(next() < 0.85 ? 1 : 0.5)))
                    }
                    x += step
                }
                y += step
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Overlays the paper grain on this view without touching hit-testing or
    /// accessibility. Used on chrome surfaces only — never on live text rows
    /// dense enough that the grain would sit over glyphs at full strength.
    func paperTexture(seed: UInt64 = 7, opacity: Double = 0.035) -> some View {
        overlay(PaperGrain(seed: seed, opacity: opacity))
    }
}

// MARK: - Logo mark

/// The FleetConsole mark, struck like a rubber stamp: a bordered plate, a
/// glyph, and two degrees of rotation so it reads as pressed, not printed.
struct FleetMark: View {
    var size: CGFloat = 22
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(ConsoleColor.numeral.opacity(0.55), lineWidth: 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(ConsoleColor.numeral.opacity(colorScheme == .dark ? 0.06 : 0.04))
                )
            Text("FC")
                .font(StampFont.display(max(16, size * 0.72)))
                .tracking(StampFont.tracking)
                .foregroundStyle(ConsoleColor.numeral.opacity(0.8))
        }
        .frame(width: size * 1.45, height: size)
        .rotationEffect(.degrees(-2))
        .accessibilityLabel("FleetConsole")
    }
}
