import AppKit
import SwiftUI
import FleetCore

/// One menu-bar item: status glyph, popover, dropdown menu.
///
/// FleetConsole puts up exactly one of these. The class stayed generic through
/// the collapse from five items to two to one — it knows how to render a summary
/// and show a popover, and nothing about a surface's *content* lives here — but
/// the count in this comment did not, and it went on claiming a second Network
/// item for as long as `docs/DESIGN-SYSTEM.md` did.
@MainActor
final class MenuBarItemController: NSObject {
    struct Summary: Equatable {
        var glyph: Glyph
        var text: String
        /// nil renders as a template image, which follows the menu-bar tint.
        var tint: StatusTone?
        var tooltip: String
        var accessibilityLabel: String
    }

    /// What the item wears on the left. The fleet item shows the wordmark while
    /// everything is fine and a state symbol when it is not, so having a brand in
    /// the menu bar never costs a signal.
    enum Glyph: Equatable {
        case symbol(String)
        case wordmark
    }

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let summaryProvider: () -> Summary
    private let menuProvider: () -> NSMenu
    private let onWillOpen: () -> Void
    private var lastRendered: Summary?

    init(identifier: String,
         contentView: some View,
         summary: @escaping () -> Summary,
         menu: @escaping () -> NSMenu,
         onWillOpen: @escaping () -> Void = {}) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // macOS remembers a named item's position, so ⌘-dragging the three
        // together survives relaunch instead of scattering again.
        self.statusItem.autosaveName = "com.fleetconsole.item.\(identifier)"
        self.summaryProvider = summary
        self.menuProvider = menu
        self.onWillOpen = onWillOpen
        super.init()

        popover.behavior = .transient
        popover.animates = true

        // `sizingOptions` is what makes the hosting controller keep
        // `preferredContentSize` in step with SwiftUI's ideal size. Without it
        // the controller reports nothing until after its first layout, so
        // `NSPopover` positions itself against a size it does not have yet — and
        // the repositioning it would otherwise do to keep a popover on screen
        // never happens. On a status item near the right edge of the display,
        // the 380pt content then ran off the screen with its trailing column
        // cut off.
        let hosting = NSHostingController(rootView: AnyView(contentView))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        if let button = statusItem.button {
            button.action = #selector(clicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        refresh()
    }

    /// Re-renders only when the summary actually changed, so the 1 Hz clock that
    /// drives lease countdowns never touches the menu bar.
    func refresh() {
        guard let button = statusItem.button else { return }
        let summary = summaryProvider()
        guard summary != lastRendered else { return }
        lastRendered = summary

        switch summary.glyph {
        case .wordmark:
            button.image = FleetWordmark.image(accessibilityDescription: summary.accessibilityLabel)
        case .symbol(let name):
            var configuration = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .medium)
            if let tint = summary.tint {
                // Colour only when something is wrong; a permanently coloured icon is
                // one more thing you learn to stop seeing.
                let colour: NSColor = tint == .bad ? .systemRed : .systemOrange
                configuration = configuration.applying(.init(paletteColors: [colour]))
            }
            let image = NSImage(systemSymbolName: name, accessibilityDescription: summary.accessibilityLabel)
            image?.isTemplate = summary.tint == nil
            button.image = image?.withSymbolConfiguration(configuration)
        }

        button.attributedTitle = NSAttributedString(
            string: summary.text.isEmpty ? "" : " \(summary.text)",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)])
        button.toolTip = summary.tooltip
        button.setAccessibilityLabel("\(summary.accessibilityLabel). \(summary.text)")
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            let menu = menuProvider()
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            toggle(sender)
        }
    }

    private func toggle(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    /// Opens the popover as a left-click would, including the `onWillOpen`
    /// refresh. Used by the dropdown's Network item, which is a request to see a
    /// popover section rather than to open the console window.
    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        onWillOpen()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        popover.performClose(nil)
    }
}

// MARK: - Wordmark

/// The FleetConsole mark: a geometric F with one arc of the fleet mesh.
///
/// Drawn rather than shipped as an image asset so it stays crisp on any display
/// and behaves exactly like an SF Symbol does — a template image that follows
/// the menu bar through light, dark and the accent-tinted variants, with no
/// @2x/@3x set to keep in sync.
///
/// `Scripts/appicon/Icon.swift` draws the app icon from these same proportions,
/// so the Finder icon and this glyph are one letter rather than two drawings of
/// one. Change the geometry here and re-run `Scripts/make-icon.sh`.
@MainActor
enum FleetWordmark {
    private static var cached: NSImage?

    static func image(accessibilityDescription: String) -> NSImage {
        if let cached {
            cached.accessibilityDescription = accessibilityDescription
            return cached
        }
        let made = render()
        made.accessibilityDescription = accessibilityDescription
        cached = made
        return made
    }

    private static func render() -> NSImage {
        // A compact geometric F: a single, repeatable silhouette at 16pt rather
        // than a script glyph whose swashes dissolve in the menu bar. One arc of
        // the app icon's fleet mesh hangs off it, struck from the same point the
        // icon strikes its arcs from — the foot of the stem.
        //
        // Only one arc, and the arms stay straight. Bending the arms into arcs
        // closes the letter into something that reads as an R, and the mesh on
        // its own — concentric arcs from a corner — is the Wi-Fi glyph, which in
        // a menu bar is sitting three icons away from this one.
        //
        // No mesh arc. `Scripts/appicon/Icon.swift` draws this same letter, and
        // its `Detail.forCanvas` drops the mesh entirely at 16 and 32pt — "the
        // letter alone. Arcs at this size are one grey pixel wide and read as
        // dirt on the plate." This glyph is 16pt and was striking an arc anyway,
        // at radius 12 across 34° of sweep: too little curvature at that radius
        // to read as an arc, so it rendered as a straight diagonal hanging off
        // the top arm — an F with a slash through it rather than a mark. The two
        // drawings now agree at the size they share.
        //
        // 15pt square, not 16 wide: the 16th point existed only to clear that
        // arc's outer end. The letter runs x 2.2…12.6 and y 1.2…13.8, so a 15pt
        // box leaves it centred.
        //
        // Drawn through `NSImage(size:flipped:drawingHandler:)` rather than
        // `lockFocus()`. Both produce an `NSImage`, but `lockFocus` rasterizes
        // once, at whatever backing scale happened to be current on the first
        // call, and this image is then cached for the life of the process — so
        // the "stays crisp on any display" this mark was drawn rather than
        // shipped for was not actually true: a menu bar dragged from a Retina
        // display to a 1x one, or an app launched before the external display
        // woke, kept the stale raster. The drawing handler is re-invoked per
        // scale by AppKit, which is the property that was wanted.
        let size = NSSize(width: 15, height: 15)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            let bar: CGFloat = 2.4
            let radius = bar / 2
            NSBezierPath(roundedRect: NSRect(x: 2.2, y: 1.2, width: bar, height: 12.6),
                         xRadius: radius, yRadius: radius).fill()
            NSBezierPath(roundedRect: NSRect(x: 3.4, y: 11.4, width: 9.2, height: bar),
                         xRadius: radius, yRadius: radius).fill()
            NSBezierPath(roundedRect: NSRect(x: 3.4, y: 6.4, width: 6.7, height: bar),
                         xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

}
