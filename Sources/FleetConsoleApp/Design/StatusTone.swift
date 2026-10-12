import SwiftUI
import FleetCore

// Shared vocabulary for status. Shape carries the meaning as well as colour, so
// the menu bar and the dashboard stay readable without relying on colour alone.
//
// Lives in Design/ rather than in Views/Components.swift, where it started.
// The design system has always said this is "the only place a status colour is
// chosen", and the audit exempts Design/ from the no-inline-hues rule on exactly
// that basis — but the enum was in the view layer, so the exemption did not
// reach it and the vocabulary's own definition read as three violations.
// A rule whose one legitimate exception has to be special-cased by filename is
// a rule with the file in the wrong place.

/// The achromatic inks and washes, named once.
///
/// `FleetColor` (popover ramp) and `ConsoleColor` (window ramp) both expose
/// these rather than defining their own, and that is deliberate: the two ramps
/// differ in **type and metrics** — a 13pt menu row and a dynamic-type window row
/// are different reading distances — but "a measured value" and "a surface at
/// rest" mean the same thing on both, and giving them two values would be the
/// 9/9.5 font-size pair again. The ramp separation is about size, not about
/// vocabulary.
///
/// Before these there were seven strengths of `Color.primary.opacity(…)` across
/// the view layer — 0.04, 0.06, 0.7, 0.75, 0.8, 0.85, 0.9 — for four ideas.
enum SurfaceInk {
    static var secondary: Color { Color(nsColor: .secondaryLabelColor) }
    /// A measured value: monospaced digits in a row, a stat tile's numeral, a
    /// byte count. Data rather than a label, so it sits one step below
    /// `.primary` without dropping to `.secondary`, which means *supporting
    /// text* and would put a resident-memory figure at the same weight as the
    /// word beside it.
    static var numeral: Color { Color(nsColor: .labelColor) }

    /// An untinted surface at rest — a chip, a card, a capsule that is not
    /// carrying a status.
    static var surfaceWash: Color { Color.primary.opacity(0.04) }

    /// The same surface under the pointer. Rows never scale or change weight;
    /// this is the whole hover vocabulary.
    static var hoverWash: Color { Color.primary.opacity(0.06) }

    /// The same surface, selected. Distinct from hover, because a row can be
    /// both and the two states have to be told apart without colour.
    static var selectedWash: Color { Color.primary.opacity(0.10) }

    /// A filled indicator segment that is not a status — a signal bar that is
    /// lit, a step that is complete.
    static var indicatorOn: Color { Color.primary.opacity(0.75) }

    /// The unlit half of the same indicator. Grey rather than faint-primary, so
    /// the pair reads as *four bars, two lit* rather than as a gradient.
    static var indicatorOff: Color { Color.secondary.opacity(0.25) }

    /// A value that is absent, or a control that is unavailable. One step under
    /// `.secondary`, which is as far as text can go and still be read — the two
    /// literals this replaced were 0.5 and 0.6, and nothing distinguished them.
    static var dim: Color { Color.secondary.opacity(0.6) }

    /// An untinted border on a control — a capsule, a chip, a picker segment.
    static var outline: Color { Color.primary.opacity(0.3) }

    /// The same border where it has to survive a saturated fill underneath it:
    /// a selection ring on a heatmap tile, where `outline` would vanish.
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

    /// The tone at *text* weight — what a word or glyph is drawn in when it sits
    /// on that tone's own tinted fill (`Tag`, `ConsoleBadge`, `EvidenceChips`).
    ///
    /// `color` is a **fill** colour, and reusing it as small text on a 14% tint of
    /// itself measures 1.98:1 for `good`, 2.06:1 for `warn` and 2.95:1 for `bad`
    /// in light mode — every tone under WCAG AA's 4.5:1, on operational labels
    /// like "Expired", "Leaked" and "Unmanaged" that are meant to be read at a
    /// glance. The same colours measure 4.17–6.34:1 in dark mode, because a
    /// saturated system hue against a dark fill is doing a different job than
    /// against a pale one. So the correction is per-appearance rather than one
    /// darker green: the hue moves toward the label colour by the smallest
    /// fraction that clears AA on its own fill, solved per appearance against
    /// `NSColor.blended` itself (light needed 26–43%, dark 0–8%) and rounded up
    /// once for all three rather than tuned per tone.
    ///
    /// `neutral` and `unknown` are greys derived from `secondaryLabelColor`, which
    /// is translucent by definition — their text and their fill darken together,
    /// so no blend reaches 4.5:1. They resolve to the system's own secondary label
    /// instead, which is 3.83:1 here: the contrast macOS itself ships for
    /// secondary text, and above the 3:1 floor for UI components. `unknown`
    /// previously halved that again to 1.82:1, which is what actually needed
    /// fixing.
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

    // MARK: Tints
    //
    // A tone is used at four strengths, and before these existed it was used at
    // nine: 0.07 and 0.08 and 0.10 for the same row wash, 0.12 and 0.13 and 0.14
    // and 0.16 for the same chip fill, across seven files. That is the ~130
    // literal font sizes again, in colour — nobody chose those numbers, they were
    // each typed once next to whatever was already on screen.
    //
    // Four strengths, because there are four jobs. Anything that needs a fifth
    // is either one of these four or a new named token, never a fresh literal.

    /// A tinted background behind a whole row or banner. The faintest of the
    /// four: it has to read as *this row is warm* under body text, without the
    /// text having to fight it.
    var wash: Color { color.opacity(0.08) }

    /// The fill under a chip, tag or badge — a small shape whose own bounds
    /// carry the tint, so it can be stronger than a row wash without shouting.
    /// This is the 14% the `ink` contrast solution was solved against.
    var chipFill: Color { color.opacity(0.14) }

    /// A tinted border. Strong enough to read as a deliberate edge at one point
    /// wide, which a wash is not.
    var edge: Color { color.opacity(0.35) }

    /// A tinted line — a sparkline, a meter's outline. A stroke is one point of
    /// coverage against the background, so it needs most of the hue to survive.
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

    /// The tone as a *bare* glyph, for anywhere status has to survive without
    /// colour: an evidence chip, a badge, a pip under Differentiate Without Colour.
    ///
    /// This exists because `symbol` cannot do that job, and the reason is
    /// measurable rather than aesthetic. Rendered as silhouettes at 8–13pt and
    /// compared pairwise by intersection-over-union, every *enclosed* badge
    /// vocabulary bottoms out around 0.85–0.91 on its worst pair — `circle.fill`
    /// against `xmark.octagon.fill` is 0.87, and the obvious "more native" swap to
    /// `checkmark.circle.fill` / `questionmark.circle.fill` makes it *worse* (0.91),
    /// because a filled circle and a filled octagon are the same blob once the
    /// glyph inside them is two points wide. The enclosure is the problem: it is
    /// most of the ink and it is common to every tone. Dropping it takes the worst
    /// pair to **0.24**. So the enclosed `symbol` stays for the standalone dot,
    /// where colour is doing the work and the ring is what makes it read as a
    /// deliberate indicator — and `verdict` is what gets used when colour cannot
    /// be relied on.
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

    /// What the state means for you, in one sentence.
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

    /// Never says "healthy" unless a health check actually passed.
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
