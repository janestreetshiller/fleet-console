import SwiftUI

/// The middle column's modules. Order is the order in the toolbar picker and
/// the order of the ⌘1…⌘6 shortcuts.
///
/// It lives in `Design/` rather than beside `ConsoleModel`, for the same reason
/// `StatusTone` does: the list is a design declaration before it is navigation
/// state. `ConsoleMetrics.modulePickerWidth` is a function of `allCases.count`,
/// so with the enum in the view layer a token in `Design/Tokens.swift` reached
/// *up* into `Views/Console/` for its value — and `Scripts/fleetkit-sheet.sh`,
/// which symlinks the design sources into a throwaway package so the contact
/// sheet renders what actually ships, could not resolve the picker width at all
/// without dragging `ConsoleModel`, `AppModel` and the rest of the console in
/// behind it. The alternatives were a stubbed module list in the sheet, which
/// makes the one number the sheet exists to show a fiction, or this.
///
/// Nothing here depends on the console's object graph — the symbol, the raw
/// label and the digit index are all the enum's own.
enum ConsoleModule: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case processes = "Processes"
    case storage = "Storage"
    case services = "Services"
    case events = "Events"
    case plists = "Launch Services"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.bottom.50percent"
        case .processes: return "gearshape.2"
        case .storage: return "internaldrive"
        case .services: return "square.stack.3d.up"
        case .events: return "list.bullet.rectangle"
        case .plists: return "scroll"
        }
    }

    /// Keyboard equivalent in the View menu (⌘1…).
    var shortcutIndex: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }
}
