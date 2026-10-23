import SwiftUI
import AppKit

// One heatmap engine for every map in the console.
//
// The first operations map shipped its own layout; the storage map was about
// to grow a second. There is now one: a squarified (Bruls–Huizing–van Wijk)
// treemap, because the naive slice-and-dice layout degenerates into slivers,
// and a sliver is neither readable nor clickable.
//
// Encoding rules, applied to both maps:
//
//   * **Area is the quantity.** Area is the only visual channel people read
//     accurately without a legend, and "where did it go" is always an area
//     question.
//   * **Colour never repeats area.** On the disk map colour is the storage
//     category; on the process map it is CPU activity (the market-cap/day's-
//     move rule — size says how much, colour says whether to act).
//   * **Every byte is accounted for.** A capped tail and small entries roll
//     into a remainder tile rather than vanishing, so the map's areas sum to
//     the number above it.
//   * **Labels only where they fit.** Hover and the readout line carry the
//     rest; a truncated word in a 20pt tile is noise.

// MARK: - Model

struct HeatmapItem: Identifiable, Equatable {
    /// What tapping the tile does.
    enum Action: Equatable {
        /// Reveal this path in Finder.
        case reveal(String)
        /// Select this pid in the Processes module.
        case selectPID(Int32)
        /// Informational only (remainder tiles).
        case none
    }

    let id: String
    var name: String
    /// Secondary line for the readout (path, process count…).
    var detail: String
    /// Area.
    var bytes: Int64
    /// Category or tone colour — never size.
    var color: Color
    var labelColor: Color
    /// Roll-up tile: small entries, the capped tail. Drawn dimmed.
    var isRemainder = false
    var action: Action = .none
    var processStartSignature: String?
}

// MARK: - Squarified layout

enum SquarifiedLayout {
    /// Frames for `values` packed into `rect`, one per value, in input order.
    /// Degenerate input yields an empty array, never NaN frames.
    static func frames(for values: [Double], in rect: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard !values.isEmpty, total > 0, rect.width > 1, rect.height > 1 else { return [] }

        let scale = (rect.width * rect.height) / CGFloat(total)
        let areas = values.map { CGFloat($0) * scale }
        var frames = [CGRect](repeating: .zero, count: values.count)
        var remaining = rect
        var index = 0

        while index < values.count {
            let side = min(remaining.width, remaining.height)
            var rowEnd = index
            var rowArea = areas[index]

            // Grow the current row while adding the next tile *improves* the
            // row's worst aspect ratio — the entire trick in one comparison.
            while rowEnd + 1 < values.count {
                let candidate = rowArea + areas[rowEnd + 1]
                guard worstAspect(areas, index...rowEnd + 1, rowArea: candidate, side: side)
                        < worstAspect(areas, index...rowEnd, rowArea: rowArea, side: side)
                else { break }
                rowEnd += 1
                rowArea = candidate
            }

            layoutRow(areas, index...rowEnd, rowArea: rowArea,
                      remaining: &remaining, frames: &frames)
            index = rowEnd + 1
        }
        return frames
    }

    /// The row's worst side ratio, in the closed Bruls form: for a row of area
    /// R laid along a side of length s, the extremes depend only on the row's
    /// largest and smallest tile.
    private static func worstAspect(_ areas: [CGFloat], _ range: ClosedRange<Int>,
                                    rowArea: CGFloat, side: CGFloat) -> CGFloat {
        guard side > 0, rowArea > 0 else { return .infinity }
        var largest: CGFloat = 0
        var smallest: CGFloat = .infinity
        for i in range {
            largest = max(largest, areas[i])
            smallest = min(smallest, areas[i])
        }
        let s2 = side * side
        let r2 = rowArea * rowArea
        return max(s2 * largest / r2, r2 / (s2 * smallest))
    }

    /// Commits one row: a vertical strip down the left when the remaining
    /// space is wider than tall, a horizontal strip across the top otherwise.
    private static func layoutRow(_ areas: [CGFloat], _ range: ClosedRange<Int>,
                                  rowArea: CGFloat, remaining: inout CGRect,
                                  frames: inout [CGRect]) {
        if remaining.width >= remaining.height {
            let stripWidth = remaining.height > 0 ? rowArea / remaining.height : 0
            var y = remaining.minY
            for i in range {
                let height = stripWidth > 0 ? areas[i] / stripWidth : 0
                frames[i] = CGRect(x: remaining.minX, y: y, width: stripWidth, height: height)
                y += height
            }
            remaining.origin.x += stripWidth
            remaining.size.width = max(0, remaining.size.width - stripWidth)
        } else {
            let stripHeight = remaining.width > 0 ? rowArea / remaining.width : 0
            var x = remaining.minX
            for i in range {
                let width = stripHeight > 0 ? areas[i] / stripHeight : 0
                frames[i] = CGRect(x: x, y: remaining.minY, width: width, height: stripHeight)
                x += width
            }
            remaining.origin.y += stripHeight
            remaining.size.height = max(0, remaining.size.height - stripHeight)
        }
    }
}

// MARK: - View

struct HeatmapView: View {
    let items: [HeatmapItem]
    /// The honesty line shown when nothing is hovered.
    var summary: String?
    /// Live process samples should not animate dozens of tile frames each tick.
    var animatesLayout = true
    var investigationModel: AppModel?

    @State private var hovered: HeatmapItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLiveResizing) private var isLiveResizing

    private var sorted: [HeatmapItem] {
        items.sorted { $0.bytes > $1.bytes }
    }

    /// Tiles move on their own frame, not on the data.
    ///
    /// The map used to carry one `.animation(_:value: items)` on the stack
    /// outside the `GeometryReader`, which animated a *data* change and nothing
    /// else. Every tile's rectangle is computed from `geometry.size` inside that
    /// reader, so resizing the window, opening the inspector or dragging a tool
    /// panel changed all forty rectangles with `items` untouched — the one value
    /// being watched — and the whole map snapped to its new layout in a single
    /// frame. That is the case you actually see most often, and it was the one
    /// case not animated.
    ///
    /// Keying each tile on its own `frame` covers both causes with one rule,
    /// because a squarified relayout *is* a set of frame changes whatever
    /// provoked it.
    private var layoutAnimation: Animation? {
        // A live drag is the third case, and it was the one this rule got
        // wrong. Keying tiles on their own frame was right — a squarified
        // relayout *is* a set of frame changes — but a resize changes all forty
        // rectangles on every frame of the gesture, so a 0.55s spring was being
        // restarted forty times over, sixty times a second. The map turned to
        // jelly under the pointer, which is the most visible thing in the
        // window and the reason resizing felt chewy. The container is already
        // tracking the drag directly; the tiles inside it have to as well.
        (!animatesLayout || reduceMotion || isLiveResizing) ? nil : ConsoleAnimation.mapLayout
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let frames = SquarifiedLayout.frames(
                    for: sorted.map { Double($0.bytes) },
                    in: CGRect(origin: .zero, size: geometry.size))
                ZStack(alignment: .topLeading) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, item in
                        if index < frames.count, frames[index].width > 2, frames[index].height > 2 {
                            tile(item, frame: frames[index])
                        }
                    }
                }
            }
            readout
        }
        // Tiles entering and leaving — a process starting, a scan finishing —
        // still fade rather than blink into existence. The movement of the ones
        // that stay is the tile's own business, above.
        .animation(layoutAnimation, value: items)
    }

    // MARK: Tile

    private func tile(_ item: HeatmapItem, frame: CGRect) -> some View {
        let request: InvestigationRequest? = {
            guard let model = investigationModel, case .selectPID(let pid) = item.action,
                  let row = model.processes.row(pid), row.startSignature == item.processStartSignature else { return nil }
            return .process(row, model: model)
        }()
        let isHovered = hovered?.id == item.id
        let shape = RoundedRectangle(cornerRadius: ConsoleMetrics.mapTileCorner, style: .continuous)
        // The tile is drawn inside its computed rectangle, not on it. Neighbours
        // are separated by a channel of the card behind them rather than by a
        // stroke, which is what makes a mass read as a mass:
        //
        //   * A 0.5pt edge at 18% black — what this drew before — is invisible
        //     against the saturated fills and nearly invisible in dark mode, so
        //     two adjacent green tiles of similar size merged into one shape and
        //     the map lost exactly the boundary it exists to show.
        //   * A heavier stroke would only trade that for a grid of dark lines
        //     over a map whose subject is area.
        //   * A gutter costs no colour decision at all, survives both
        //     appearances and every fill the maps can produce, and lands on
        //     whole pixels at any scale factor, so the edges stay crisp instead
        //     of half-covering a pixel row.
        //
        // It is also the honest encoding. Every tile gives up the same margin,
        // so the *ratios* between masses — the only thing a treemap actually
        // claims — are preserved, while no tile pretends its rectangle is a
        // measurement you could read a byte count off.
        let inset = ConsoleMetrics.mapTileGutter / 2
        let drawn = frame.insetBy(dx: inset, dy: inset)
        return ZStack(alignment: .topLeading) {
            shape
                .fill(item.color.opacity(item.isRemainder ? ConsoleColor.remainderDim : 1))
                .overlay {
                    // Two-ply ring: see `ConsoleColor.tileHoverRing`. A single
                    // ink cannot survive both a saturated fill and a pale grey.
                    if isHovered {
                        shape.strokeBorder(ConsoleColor.tileHoverRing, lineWidth: 1.5)
                        shape.strokeBorder(ConsoleColor.tileHoverShade, lineWidth: 1)
                            .padding(1.5)
                    }
                }
                .brightness(isHovered ? 0.08 : 0)

            if drawn.width > 56, drawn.height > 28 {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.name)
                        .font(ConsoleFont.badge)
                        .lineLimit(1)
                    if drawn.height > 44 {
                        Text(ConsoleFmt.bytes(item.bytes))
                            .font(ConsoleFont.mono(.caption2))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(item.labelColor.opacity(item.isRemainder ? 0.75 : 1))
                .padding(5)
            }
        }
        .frame(width: max(0, drawn.width), height: max(0, drawn.height))
        .offset(x: drawn.minX, y: drawn.minY)
        .animation(layoutAnimation, value: frame)
        .onHover { inside in
            hovered = inside ? item : (hovered?.id == item.id ? nil : hovered)
        }
        .onTapGesture(count: 2) { if let model = investigationModel, let request { model.investigate(request) } }
        .onTapGesture { activate(item) }
        .contextMenu {
            if let model = investigationModel, let request {
                Button("Investigate heaviest process with agent") { model.investigate(request) }
            }
        }
        .accessibilityAction(named: "Investigate heaviest process with agent") {
            if let model = investigationModel, let request { model.investigate(request) }
        }
        .focusable(item.action != .none)
        .onKeyPress(keys: [.return, .space], phases: .down) { _ in
            guard item.action != .none else { return .ignored }
            activate(item)
            return .handled
        }
        .help("\(item.name) — \(ConsoleFmt.bytes(item.bytes))\n\(item.detail)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(ConsoleFmt.bytes(item.bytes))")
        // Tiles act — reveal in Finder, select the pid — so they have to be
        // buttons to VoiceOver too. A tap gesture is invisible to it, which put
        // the map's whole way-in behind a pointer. Remainder tiles do nothing
        // and say so by not claiming the trait.
        .accessibilityAddTraits(item.action == .none ? [] : [.isButton])
        .accessibilityHint(accessibilityHint(item))
        .accessibilityAction { activate(item) }
    }

    /// What activating the tile does, said before it happens.
    private func accessibilityHint(_ item: HeatmapItem) -> String {
        switch item.action {
        case .reveal: return "Reveals \(item.detail) in Finder"
        case .selectPID: return "Selects this app in the Processes module"
        case .none: return item.detail
        }
    }

    // MARK: Readout

    private var readout: some View {
        HStack(spacing: 8) {
            if let hovered {
                Swatch(color: hovered.color)
                Text(hovered.name)
                    .font(ConsoleFont.caption.weight(.medium))
                    .lineLimit(1)
                Text(ConsoleFmt.bytes(hovered.bytes))
                    .font(ConsoleFont.mono(.caption))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(hovered.detail)
                    .font(ConsoleFont.mono(.caption2))
                    .foregroundStyle(SurfaceInk.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let summary {
                Text(summary)
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .frame(minHeight: 18)
        .animation(ConsoleAnimation.selection, value: hovered?.id)
    }

    private func activate(_ item: HeatmapItem) {
        switch item.action {
        case .reveal(let path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case .selectPID(let pid):
            NotificationCenter.default.post(
                name: .init("com.fleetconsole.console.selectPID"),
                object: nil, userInfo: ["pid": pid])
        case .none:
            break
        }
    }
}
