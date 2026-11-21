import SwiftUI
import AppKit

struct OurosAppBadge<Mark: View>: View {
    var size: CGFloat = 28
    var plate: Color?
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

struct FleetBadgeMark: View {
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

@MainActor
enum FleetBrand {
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
