import SwiftUI
import FleetCore

enum SurfaceInk {
    static var secondary: Color { Color(nsColor: .secondaryLabelColor) }
    static var numeral: Color { Color(nsColor: .labelColor) }

    static var surfaceWash: Color { Color.primary.opacity(0.04) }

    static var hoverWash: Color { Color.primary.opacity(0.06) }

    static var selectedWash: Color { Color.primary.opacity(0.10) }

    static var indicatorOn: Color { Color.primary.opacity(0.75) }

    static var indicatorOff: Color { Color.secondary.opacity(0.25) }

    static var dim: Color { Color(nsColor: .secondaryLabelColor) }

    static var outline: Color { Color.primary.opacity(0.3) }

    static var outlineStrong: Color { Color.primary.opacity(0.55) }
}

enum StatusTone {
    case good, warn, bad, neutral, unknown

    var color: Color {
        switch self {
        case .good: return .green
        case .warn: return .orange
        case .bad: return .red
        case .neutral: return .secondary
        case .unknown: return Color.secondary.opacity(0.5)
        }
    }

    var ink: Color {
        switch self {
        case .neutral, .unknown:
            return Color(nsColor: .secondaryLabelColor)
        case .good, .warn, .bad:
            let base = self
            return Color(nsColor: NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(base.color).blended(withFraction: dark ? 0.12 : 0.46,
                                                   of: .textColor) ?? NSColor(base.color)
            })
        }
    }

    var wash: Color { color.opacity(0.08) }

    var chipFill: Color { color.opacity(0.14) }

    var edge: Color { color.opacity(0.35) }

    var stroke: Color { color.opacity(0.75) }

    var symbol: String {
        switch self {
        case .good: return "circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .bad: return "xmark.octagon.fill"
        case .neutral: return "circle"
        case .unknown: return "questionmark.circle"
        }
    }

    var verdict: String {
        switch self {
        case .good: return "checkmark"
        case .warn: return "exclamationmark"
        case .bad: return "xmark"
        case .neutral: return "minus"
        case .unknown: return "questionmark"
        }
    }
}

extension ServiceState {
    var tone: StatusTone {
        switch self {
        case .healthy: return .good
        case .running: return .good
        case .starting: return .neutral
        case .degraded, .expiring: return .warn
        case .unhealthy, .crashed, .expired: return .bad
        case .stopping: return .warn
        case .paused: return .neutral
        case .stopped: return .neutral
        }
    }

    var meaning: String {
        switch self {
        case .starting: return "launched and not yet confirmed alive"
        case .running: return "alive, but it has no health check, so nothing has confirmed it works"
        case .healthy: return "alive and passing its health check"
        case .degraded: return "alive, but its health check is slow or intermittently failing"
        case .unhealthy: return "alive, but its health check keeps failing"
        case .paused: return "suspended; it still holds its ports and memory"
        case .expiring: return "its owner has not renewed it and it will be stopped soon"
        case .expired: return "its owner stopped renewing it; it will be reaped"
        case .stopping: return "being shut down"
        case .stopped: return "not running"
        case .crashed: return "exited unexpectedly"
        }
    }

    var label: String {
        switch self {
        case .starting: return "Starting"
        case .running: return "Running (unverified)"
        case .healthy: return "Healthy"
        case .degraded: return "Degraded"
        case .unhealthy: return "Health check failing"
        case .paused: return "Paused (still holding ports)"
        case .expiring: return "Lease expiring"
        case .expired: return "Lease expired"
        case .stopping: return "Stopping"
        case .stopped: return "Stopped"
        case .crashed: return "Crashed"
        }
    }
}

extension DeviceHealth {
    var tone: StatusTone {
        switch self {
        case .reachable: return .good
        case .partial: return .warn
        case .unreachable: return .bad
        case .unknown: return .unknown
        }
    }
}
