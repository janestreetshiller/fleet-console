import SwiftUI
import AppKit

// The Ouros app identity, in three sizes of one idea: the badge, the badge with
// its name and one live line, and that row as the profile card that closes a
// sidebar. Nothing here knows about FleetConsole — the mark and the words are
// the caller's — so every Ouros app can wear the same three pieces.

/// The product's mark on its app icon's plate, at the macOS icon's corner
/// ratio, so the badge reads as the icon in the Dock shrunk to a row.
struct OurosAppBadge<Mark: View>: View {
    var size: CGFloat = 28
    /// The icon's plate colour. The badge is an icon, so it keeps its own
    /// colours in light and dark rather than following the window's ink.
    var plate: Color = FleetBrand.paper
    /// Drawn at the side length it is handed, inside the plate's margin.
    @ViewBuilder var mark: (CGFloat) -> Mark

    private static var rim: Color { Color.black.opacity(0.18) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        shape
            .fill(plate)
            .overlay { mark(size * 0.9) }
            .overlay { shape.strokeBorder(Self.rim, lineWidth: 0.5) }
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

/// FleetConsole's own mark for the badge: the engraved emblem, or the drawn F
/// if the emblem could not be loaded.
struct FleetBadgeMark: View {
    let size: CGFloat
    var body: some View {
        if let emblem = FleetBrand.emblem {
            Image(nsImage: emblem)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            FleetMark(size: size, construction: false, ink: FleetBrand.ink)
        }
    }
}

/// FleetConsole's brand assets: the engraved emblem and the paper it is
/// printed on, shared by the badge and the app icon.
@MainActor
enum FleetBrand {
    static let paper = Color(.sRGB, red: 247 / 255, green: 241 / 255, blue: 229 / 255)
    static let ink = Color(.sRGB, red: 22 / 255, green: 20 / 255, blue: 18 / 255)

    /// Looked up by hand rather than through SwiftPM's `Bundle.module`, whose
    /// generated accessor checks the .app's root — where a signed bundle cannot
    /// hold a resource bundle — and then a build-machine path, and traps when
    /// both miss. `assemble-app.sh` copies the bundle into Contents/Resources;
    /// in a development build it sits beside the executable.
    static let emblem: NSImage? = {
        let name = "FleetConsole_FleetConsoleApp.bundle"
        let roots = [Bundle.main.resourceURL, Bundle.main.executableURL?.deletingLastPathComponent()]
        for root in roots.compactMap({ $0 }) {
            guard let bundle = Bundle(url: root.appendingPathComponent(name)),
                  let url = bundle.url(forResource: "fleet-emblem", withExtension: "png"),
                  let image = NSImage(contentsOf: url) else { continue }
            return image
        }
        return nil
    }()
}
