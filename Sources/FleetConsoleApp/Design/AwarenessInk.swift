import SwiftUI
import AppKit

/// Semantic canvas materials. Relationships use the user accent; selection is
/// an outline, not an orange surface with appearance-dependent text.
enum AwarenessMetrics {
    static let minimapSize = CGSize(width: 144, height: 89)
}

enum AwarenessInk {
    static var ground: Color { Color(nsColor: .underPageBackgroundColor) }
    static var node: Color { Color(nsColor: .controlBackgroundColor) }
    static var edge: Color { Color(nsColor: .separatorColor) }
    static var connection: Color { Color(nsColor: .secondaryLabelColor).opacity(0.35) }
    static var grid: Color { Color(nsColor: .secondaryLabelColor).opacity(0.09) }
    static var halo: Color { Color.accentColor.opacity(0.055) }
    static var selectedHalo: Color { Color.accentColor.opacity(0.12) }
    static var shadow: Color { Color.black.opacity(0.10) }
    static var crystalFacet: Color { Color.accentColor.opacity(0.065) }
    static var crystalBranch: Color { Color(nsColor: .secondaryLabelColor).opacity(0.42) }
    static var crystalVertex: Color { Color(nsColor: .secondaryLabelColor).opacity(0.70) }
    static let faded: Double = 0.25
}
