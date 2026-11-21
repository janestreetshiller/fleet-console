import SwiftUI
import AppKit

struct HeatmapItem: Identifiable, Equatable {
    enum Action: Equatable {
        case reveal(String)
        case selectPID(Int32)
        case none
    }

    let id: String
    var name: String
    var detail: String
    var bytes: Int64
    var color: Color
    var labelColor: Color
    var isRemainder = false
    var action: Action = .none
    var processStartSignature: String?
}

enum SquarifiedLayout {
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

struct HeatmapView: View {
    let items: [HeatmapItem]
    var summary: String?
    var animatesLayout = true
    var investigationModel: AppModel?

    @State private var hovered: HeatmapItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLiveResizing) private var isLiveResizing

    private var sorted: [HeatmapItem] {
        items.sorted { $0.bytes > $1.bytes }
    }

    private var layoutAnimation: Animation? {
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
        .animation(layoutAnimation, value: items)
    }

    private func tile(_ item: HeatmapItem, frame: CGRect) -> some View {
        let request: InvestigationRequest? = {
            guard let model = investigationModel, case .selectPID(let pid) = item.action,
                  let row = model.processes.row(pid), row.startSignature == item.processStartSignature else { return nil }
            return .process(row, model: model)
        }()
        let isHovered = hovered?.id == item.id
        let shape = RoundedRectangle(cornerRadius: ConsoleMetrics.mapTileCorner, style: .continuous)
        let inset = ConsoleMetrics.mapTileGutter / 2
        let drawn = frame.insetBy(dx: inset, dy: inset)
        return ZStack(alignment: .topLeading) {
            shape
                .fill(item.color.opacity(item.isRemainder ? ConsoleColor.remainderDim : 1))
                .overlay {
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
        .accessibilityAddTraits(item.action == .none ? [] : [.isButton])
        .accessibilityHint(accessibilityHint(item))
        .accessibilityAction { activate(item) }
    }

    private func accessibilityHint(_ item: HeatmapItem) -> String {
        switch item.action {
        case .reveal: return "Reveals \(item.detail) in Finder"
        case .selectPID: return "Selects this app in the Processes module"
        case .none: return item.detail
        }
    }

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
