import AppKit
import SwiftUI
import FleetCore

@MainActor
final class MenuBarItemController: NSObject {
    struct Summary: Equatable {
        var meters: [MenuBarMeter]
        var alert: String
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
        self.statusItem.autosaveName = "com.fleetconsole.item.\(identifier)"
        self.summaryProvider = summary
        self.menuProvider = menu
        self.onWillOpen = onWillOpen
        super.init()

        popover.behavior = .transient
        popover.animates = true

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

    func refresh() {
        guard let button = statusItem.button else { return }
        let summary = summaryProvider()
        guard summary != lastRendered else { return }
        lastRendered = summary
        Self.render(summary, on: button)
    }

    static func render(_ summary: Summary, on button: NSButton) {
        button.image = MenuBarMeters.image(summary.meters)
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

struct MenuBarMeter: Equatable {
    var label: String
    var value: String
}

@MainActor
enum MenuBarMeters {
    static let height: CGFloat = 20
    static let columnSpacing: CGFloat = 7

    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 7, weight: .semibold),
        .kern: 0.4,
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
