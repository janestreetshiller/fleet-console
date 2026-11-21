import SwiftUI

enum ConsoleModule: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case processes = "Processes"
    case storage = "Storage"
    case services = "Services"
    case events = "Events"
    case plists = "Launch Services"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Agent awareness"
        case .services: return "Operations"
        default: return rawValue
        }
    }

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

    var shortcutIndex: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }
}
