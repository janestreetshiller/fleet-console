import AppKit
import SwiftUI
import FleetCore

/// One menu-bar item: live meters, popover, dropdown menu.
///
/// FleetConsole puts up exactly one of these. The class stayed generic through
/// the collapse from five items to two to one — it knows how to render a summary
/// and show a popover, and nothing about a surface's *content* lives here — but
/// the count in this comment did not, and it went on claiming a second Network
/// item for as long as `docs/DESIGN-SYSTEM.md` did.
@MainActor
final class MenuBarItemController: NSObject {
    struct Summary: Equatable {
        /// The live readings, drawn as fixed-width meters so a value changing
        /// never shifts its neighbours along the menu bar.
        var meters: [MenuBarMeter]
        /// Attention after the meters — "!2" or "Offline" — and empty when
        /// there is nothing to act on.
        var alert: String
        /// Colours the alert. Nil while there is none.
        var tint: StatusTone?
        var tooltip: String
        var accessibilityLabel: String
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
        Self.render(summary, on: button)
    }

    /// Puts a summary on a button. The status item and the surface sheet's
    /// menu-bar capture both draw through here, so the sheet shows the item the
    /// menu bar shows.
    static func render(_ summary: Summary, on button: NSButton) {
        button.image = MenuBarMeters.image(summary.meters)
        // Colour only when something is wrong; a permanently coloured item is
        // one more thing you learn to stop seeing.
        let alertColour: NSColor = summary.tint == .bad ? .systemRed : .systemOrange
        button.attributedTitle = NSAttributedString(
            string: summary.alert.isEmpty ? "" : " \(summary.alert)",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                         .foregroundColor: alertColour])
        button.toolTip = summary.tooltip
        let readings = summary.meters.map { "\($0.label) \($0.value)" }.joined(separator: ", ")
        button.setAccessibilityLabel("\(summary.accessibilityLabel). \(readings)"
                                     + (summary.alert.isEmpty ? "" : ". \(summary.alert)"))
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

// MARK: - Meters

/// One reading in the menu bar: a short label set over its value.
struct MenuBarMeter: Equatable {
    var label: String
    var value: String
}

/// CPU, RAM and disk as three stacked label-over-value meters.
///
/// Drawn as one template image, so the readings follow the menu bar through
/// light, dark and tinted variants exactly as an SF Symbol does. Every column is
/// as wide as its widest possible value ("100%"), so the item keeps one width
/// and each number keeps one position however the readings move.
@MainActor
enum MenuBarMeters {
    /// Fits the 22pt menu bar and the 24pt notched one with the same baseline.
    static let height: CGFloat = 20
    static let columnSpacing: CGFloat = 7

    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 7, weight: .semibold),
        .kern: 0.4,
        // Template images keep alpha and drop colour: this is the secondary ink.
        .foregroundColor: NSColor.black.withAlphaComponent(0.6),
    ]
    private static let valueAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
        .foregroundColor: NSColor.black,
    ]

    static func columnWidth(for meters: [MenuBarMeter]) -> CGFloat {
        let widest = meters.map { ($0.label as NSString).size(withAttributes: labelAttributes).width }
            + [("100%" as NSString).size(withAttributes: valueAttributes).width]
        return ceil(widest.max() ?? 0)
    }

    static func image(_ meters: [MenuBarMeter]) -> NSImage {
        let column = columnWidth(for: meters)
        let count = CGFloat(max(1, meters.count))
        let size = NSSize(width: column * count + columnSpacing * (count - 1), height: height)
        // Drawn through the handler rather than `lockFocus()`, so AppKit
        // re-rasterizes per backing scale instead of keeping the first one.
        let image = NSImage(size: size, flipped: true) { _ in
            for (index, meter) in meters.enumerated() {
                let x = CGFloat(index) * (column + columnSpacing)
                draw(meter.label, attributes: labelAttributes, centeredIn: x, width: column, top: 0.5)
                draw(meter.value, attributes: valueAttributes, centeredIn: x, width: column, top: 7.5)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(_ text: String, attributes: [NSAttributedString.Key: Any],
                             centeredIn x: CGFloat, width: CGFloat, top: CGFloat) {
        let string = text as NSString
        let measured = string.size(withAttributes: attributes)
        string.draw(at: NSPoint(x: x + (width - measured.width) / 2, y: top), withAttributes: attributes)
    }
}
