import SwiftUI
import FleetCore

/// One footprint for every peer in a section, including its last row.
/// Measure at the final column width so wrapped content sets the height budget.
/// No preference/state feedback loop is needed when the window resizes.
struct QuantizedCardGrid: Layout {
    var minimumCellWidth: CGFloat = ConsoleMetrics.cardMinWidth
    /// Compact artifacts use the widest peer rather than an arbitrary minimum.
    var usesLargestIntrinsicWidth = false
    var maximumColumns: Int = .max
    var horizontalSpacing: CGFloat = ConsoleMetrics.cardGap
    var verticalSpacing: CGFloat = ConsoleMetrics.cardGap
    var quantum: CGFloat = ConsoleMetrics.gridQuantum

    private struct Measurement {
        let columns: Int
        let cell: CGSize
        let size: CGSize
    }

    private func measurement(width: CGFloat?, subviews: Subviews) -> Measurement {
        guard !subviews.isEmpty else {
            return Measurement(columns: 1, cell: .zero, size: .zero)
        }
        let minimumWidth = usesLargestIntrinsicWidth
            ? ceil((subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0) / quantum) * quantum
            : minimumCellWidth
        let width = max(0, width?.isFinite == true ? width! : minimumWidth)
        let columns = min(max(1, maximumColumns), ConsoleLayout.telemetryColumns(
            contentWidth: width, instrumentCount: subviews.count,
            minimumCardWidth: max(1, minimumWidth), gap: horizontalSpacing))
        let availableCellWidth = max(0, (width - CGFloat(columns - 1) * horizontalSpacing) / CGFloat(columns))
        let cellWidth = usesLargestIntrinsicWidth ? min(availableCellWidth, minimumWidth) : availableCellWidth
        let tallest = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
        }.max() ?? 0
        let height = ceil(tallest / quantum) * quantum
        let rows = (subviews.count + columns - 1) / columns
        return Measurement(columns: columns, cell: CGSize(width: cellWidth, height: height),
                           size: CGSize(width: width,
                                        height: CGFloat(rows) * height + CGFloat(rows - 1) * verticalSpacing))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        measurement(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        let measured = measurement(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let column = index % measured.columns
            let row = index / measured.columns
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(column) * (measured.cell.width + horizontalSpacing),
                                     y: bounds.minY + CGFloat(row) * (measured.cell.height + verticalSpacing)),
                          anchor: .topLeading, proposal: ProposedViewSize(measured.cell))
        }
    }
}
