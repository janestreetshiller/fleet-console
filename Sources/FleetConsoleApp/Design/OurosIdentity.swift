import SwiftUI
import AppKit

// The Ouros app identity, in three sizes of one idea: the badge, the badge with
// its name and one live line, and that row as the profile card that closes a
// sidebar. Nothing here knows about FleetConsole — the mark and the words are
// the caller's — so every Ouros app can wear the same three pieces.

/// The product's mark, on its icon plate or on nothing at all.
///
/// With no plate the mark is ink on whatever surface it sits on, which is how
/// it appears inside the app: a tile of another colour in the popover header
/// or the sidebar reads as a sticker on the surface rather than part of it.
/// The plate is for places that show the app *as an icon*.
struct OurosAppBadge<Mark: View>: View {
    var size: CGFloat = 28
    var plate: Color?
    /// Handed the badge's side length; the mark sets its own margin.
    @ViewBuilder var mark: (CGFloat) -> Mark

    private static var rim: Color { Color.black.opacity(0.18) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        ZStack {
            if let plate {
                shape.fill(plate)
                shape.strokeBorder(Self.rim, lineWidth: 0.5)
            }
            mark(size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Badge, product name and one live line. The line carries state, so it takes
/// the tone's ink when there is something wrong and stays secondary otherwise.
struct OurosIdentityRow<Mark: View>: View {
    let title: String
    let detail: String
    var tone: StatusTone?
    var badgeSize: CGFloat = 28
    @ViewBuilder var mark: (CGFloat) -> Mark

    var body: some View {
        HStack(spacing: 9) {
            OurosAppBadge(size: badgeSize, mark: mark)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(FleetFont.rowTitleCompact.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(FleetFont.nano)
                    .foregroundStyle(tone?.ink ?? SurfaceInk.secondary)
                    .truncationMode(.tail)
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The bottom-left card: who this is, and the one menu for account and app
/// links. A card rather than a footer, so it sits inside the sidebar's margins
/// instead of ruling a line across the whole window.
struct OurosProfileCard<Mark: View, MenuItems: View>: View {
    let title: String
    let detail: String
    var tone: StatusTone?
    @ViewBuilder var mark: (CGFloat) -> Mark
    @ViewBuilder var menuItems: () -> MenuItems

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FleetMetrics.tileCorner + 2, style: .continuous)
        HStack(spacing: 6) {
            OurosIdentityRow(title: title, detail: detail, tone: tone, mark: mark)
            Spacer(minLength: 0)
            Menu(content: menuItems) {
                Image(systemName: "ellipsis")
                    .font(FleetFont.body.weight(.medium))
                    .foregroundStyle(SurfaceInk.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: FleetMetrics.iconButtonSize, height: FleetMetrics.iconButtonSize)
            .help("Account and links")
            .accessibilityLabel("\(title) account and links")
        }
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .padding(.vertical, 8)
        .background(FleetColor.surfaceWash, in: shape)
        .overlay { shape.strokeBorder(ConsoleColor.hairline, lineWidth: 1) }
    }
}

/// FleetConsole's mark: the blackletter F, drawn as a template so it takes the
/// surface's own ink in light and dark — quiet beside the name, never a tile.
struct FleetBadgeMark: View {
    /// The badge's side length.
    let size: CGFloat
    var body: some View {
        if let letter = FleetBrand.letter {
            Image(nsImage: letter)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: size * 0.92)
                .foregroundStyle(SurfaceInk.secondary)
        } else {
            FleetMark(size: size * 0.8, construction: false, ink: SurfaceInk.secondary)
        }
    }
}

/// FleetConsole's brand asset: the blackletter F, ink on a transparent ground.
@MainActor
enum FleetBrand {
    /// Looked up by hand rather than through SwiftPM's `Bundle.module`, whose
    /// generated accessor checks the .app's root — where a signed bundle cannot
    /// hold a resource bundle — and then a build-machine path, and traps when
    /// both miss. `assemble-app.sh` copies the bundle into Contents/Resources;
    /// in a development build it sits beside the executable.
    static let letter: NSImage? = {
        let bundleName = "FleetConsole_FleetConsoleApp.bundle"
        let roots = [Bundle.main.resourceURL, Bundle.main.executableURL?.deletingLastPathComponent()]
        for root in roots.compactMap({ $0 }) {
            guard let bundle = Bundle(url: root.appendingPathComponent(bundleName)),
                  let url = bundle.url(forResource: "fleet-letter", withExtension: "png"),
                  let image = NSImage(contentsOf: url) else { continue }
            image.isTemplate = true
            return image
        }
        return nil
    }()
}
