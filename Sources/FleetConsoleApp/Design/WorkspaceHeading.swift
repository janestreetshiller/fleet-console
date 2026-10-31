import SwiftUI

/// Page identity is distinct from card headings and supporting observations.
/// Keep the system type ramp and allow the explanation to wrap at narrow widths.
struct WorkspaceHeading: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ConsoleFont.moduleTitle)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(ConsoleFont.subtitle)
                .foregroundStyle(SurfaceInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.heading")
    }
}
