import SwiftUI
import AppKit
import FleetCore

enum ChromeRailMetrics {
    static let railWidth = ConsoleToolMetrics.toggleSize + ConsoleToolMetrics.railSpacing * 2

    static let handleWidth: CGFloat = 1

    static let handleHitWidth: CGFloat = 10

    static let columnReserve = ConsoleLayout.inspectorAndPanelFloor
        - ConsoleLayout.panelMin
}

@Observable
@MainActor
final class ChromeTools {
    let registry = ToolSurfaceRegistry()

    private(set) var revealed: ConsoleTool?

    private(set) var settledGrid: TerminalGrid?

    var requestedPanelWidth = ConsoleToolMetrics.panelIdeal

    private(set) var context = ToolContext()

    @ObservationIgnored private var coalescers: [ConsoleTool: ToolResizeCoalescer] = [:]

    @ObservationIgnored private var lastProposedSize: CGSize = .zero

    func toggle(_ tool: ConsoleTool, context: ToolContext) {
        if revealed == tool {
            dismiss()
            return
        }
        if revealed != nil { dismiss() }
        self.context = context
        settledGrid = nil
        revealed = tool
        registry.surface(for: tool).activate(context: context)
    }

    @discardableResult
    func run(_ commandLine: String, in context: ToolContext) -> Bool {
        if revealed == .terminal { update(context: context) } else { toggle(.terminal, context: context) }
        return (registry.surface(for: .terminal) as? TerminalPanel)?.run(commandLine) ?? false
    }

    @discardableResult
    func startAgent(_ request: TerminalAgentRequest) -> Bool {
        guard let terminal = registry.surface(for: .terminal) as? TerminalPanel,
              terminal.startAgent(request) else { return false }
        let context = ToolContext(workingDirectory: request.workingDirectory, subject: request.subject)
        if revealed == .terminal { update(context: context) } else { toggle(.terminal, context: context) }
        return true
    }

    func investigate(_ starter: String, billing: OurosBilling, subject: String, validation: @escaping @MainActor () -> Bool) -> Bool {
        guard let terminal = registry.surface(for: .terminal) as? TerminalPanel,
              terminal.investigate(starter, billing: billing, validation: validation) else { return false }
        let context = ToolContext(subject: "Investigate · " + subject)
        if revealed == .terminal { update(context: context) } else { toggle(.terminal, context: context) }
        return true
    }

    func dismiss() {
        guard let tool = revealed else { return }
        coalescers[tool]?.reset()
        registry.surface(for: tool).deactivate()
        revealed = nil
        settledGrid = nil
    }

    func update(context: ToolContext) {
        guard self.context != context else { return }
        self.context = context
        guard let tool = revealed else { return }
        registry.surface(for: tool).activate(context: context)
    }

    func propose(size: CGSize) {
        lastProposedSize = size
        regrid()
    }

    func regrid() {
        guard let tool = revealed, tool.isPTYBacked,
              lastProposedSize.width > 0, lastProposedSize.height > 0 else { return }
        let surface = registry.surface(for: tool) as? any PTYBackedSurface
        let cell = surface?.cellMetrics ?? .placeholder
        let reserved = surface?.reservedWidth ?? 0
        let terminalHeight = lastProposedSize.height - (surface?.chromeHeight ?? 0)
        let grid = terminalHeight > 0
            ? TerminalGrid.fitting(CGSize(width: lastProposedSize.width, height: terminalHeight),
                                   cell: cell, reservedWidth: reserved)
            : TerminalGrid(columns: 1, rows: 1)
        coalescer(for: tool).propose(grid)
    }

    func invalidateGeometry() {
        guard let tool = revealed else { return }
        coalescers[tool]?.reset()
        regrid()
    }

    func flushGeometry() {
        guard let tool = revealed, tool.isPTYBacked else { return }
        coalescers[tool]?.flush()
    }

    private func coalescer(for tool: ConsoleTool) -> ToolResizeCoalescer {
        if let existing = coalescers[tool] { return existing }
        let made = ToolResizeCoalescer { [weak self] grid in
            guard let self else { return }
            self.settledGrid = grid
            self.registry.surface(for: tool).resize(to: grid)
        }
        coalescers[tool] = made
        return made
    }

    func panelWidth(outerWidth: CGFloat) -> CGFloat {
        let spare = outerWidth - ChromeRailMetrics.columnReserve
        let ceiling = min(ConsoleToolMetrics.panelMax, max(ConsoleToolMetrics.panelMin, spare))
        return min(max(ConsoleToolMetrics.panelMin, requestedPanelWidth), ceiling)
    }

    var isTooNarrow: Bool {
        guard let grid = settledGrid else { return false }
        return !grid.fitsMinimum
    }
}

struct ChromeToolField: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel
    let tools: ChromeTools

    let outerWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if let tool = tools.revealed {
                ChromeToolPanel(tool: tool, tools: tools,
                                width: tools.panelWidth(outerWidth: outerWidth))
            }
        }
    }
}

private struct ChromeRail: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel
    let tools: ChromeTools

    private var live: Set<ConsoleTool> {
        _ = model.clockTick
        return tools.registry.live
    }

    var body: some View {
        VStack(spacing: ConsoleToolMetrics.railSpacing) {
            ChromeRailButton(symbol: "house",
                             title: "Home",
                             shortcut: "⇧⌘H",
                             isOn: console.atHome && console.isLocalDeviceSelected,
                             isLive: false) {
                console.goHome()
            }

            Hairline()
                .padding(.horizontal, 2)

            let running = live
            ForEach(ConsoleTool.allCases) { tool in
                ChromeRailButton(symbol: tool.symbol,
                                 title: tool.title,
                                 shortcut: shortcutLabel(tool),
                                 isOn: tools.revealed == tool,
                                 isLive: running.contains(tool)) {
                    tools.toggle(tool, context: tools.context)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, ConsoleToolMetrics.railSpacing)
        .padding(.top, ConsoleToolMetrics.railSpacing)
        .frame(width: ChromeRailMetrics.railWidth)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ConsoleColor.hairline)
                .frame(width: 1)
        }
    }

    private func shortcutLabel(_ tool: ConsoleTool) -> String {
        "⇧⌘" + String(tool.shortcut.character).uppercased()
    }
}

private struct ChromeRailButton: View {
    let symbol: String
    let title: String
    let shortcut: String
    let isOn: Bool
    let isLive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(ConsoleFont.subtitle)
                .symbolVariant(isOn ? .fill : .none)
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: ConsoleToolMetrics.toggleSize,
                       height: ConsoleToolMetrics.toggleSize)
                .background(
                    RoundedRectangle(cornerRadius: ConsoleMetrics.rowCorner, style: .continuous)
                        .fill(isOn ? ConsoleColor.selectionFill : .clear)
                )
                .overlay(alignment: .bottomTrailing) {
                    if isLive {
                        StatusPip(tone: .good, size: 4, pulsing: true)
                            .offset(x: 3, y: 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: ConsoleMetrics.rowCorner)
        .help("\(title) (\(shortcut))")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

private struct ChromeToolPanel: View {
    let tool: ConsoleTool
    let tools: ChromeTools
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            dragHandle
            VStack(spacing: 0) {
                header
                Hairline()
                content
            }
        }
        .frame(width: width)
        .clipped()
    }

    private var cellMetrics: TerminalCellMetrics? {
        (tools.registry.surface(for: tool) as? any PTYBackedSurface)?.cellMetrics
    }

    private var terminalLayoutRevision: Int {
        (tools.registry.surface(for: tool) as? TerminalPanel)?.layoutRevision ?? 0
    }

    private var chromeHeight: CGFloat {
        (tools.registry.surface(for: tool) as? any PTYBackedSurface)?.chromeHeight ?? 0
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: tool.symbol)
                .font(ConsoleFont.caption)
                .foregroundStyle(.secondary)
            Text(tool.title)
                .font(ConsoleFont.caption.weight(.semibold))
            Text(tools.context.subject)
                .font(ConsoleFont.caption)
                .foregroundStyle(SurfaceInk.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
            Spacer(minLength: 4)
            Button {
                tools.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(ConsoleFont.badge)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close \(tool.title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if tools.isTooNarrow && tool == .files {
                EmptyPanelView(
                    symbol: tool.symbol,
                    title: "Panel too narrow",
                    detail: "\(tool.title) needs at least \(TerminalGrid.minimum.columns) columns "
                        + "and \(TerminalGrid.minimum.rows) rows to draw honestly. "
                        + "Drag the panel's edge, or widen the window.")
            } else {
                tools.registry.surface(for: tool).makeView()
                    .id(tool)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        tools.propose(size: geometry.size)
                        tools.flushGeometry()
                    }
                    .onChange(of: geometry.size) { _, size in
                        tools.propose(size: size)
                    }
            }
        }
        .onChange(of: cellMetrics) { _, _ in tools.regrid() }
        .onChange(of: chromeHeight) { _, _ in tools.regrid() }
        .onChange(of: terminalLayoutRevision) { _, _ in tools.invalidateGeometry() }
    }

    private var dragHandle: some View {
        Rectangle()
            .fill(ConsoleColor.hairline)
            .frame(width: ChromeRailMetrics.handleWidth)
            .padding(.horizontal, (ChromeRailMetrics.handleHitWidth
                                   - ChromeRailMetrics.handleWidth) / 2)
            .contentShape(Rectangle())
            .padding(.horizontal, -(ChromeRailMetrics.handleHitWidth
                                    - ChromeRailMetrics.handleWidth) / 2)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        tools.requestedPanelWidth = (width - value.translation.width)
                            .clamped(ConsoleToolMetrics.panelMin, ConsoleToolMetrics.panelMax)
                    }
                    .onEnded { _ in tools.flushGeometry() }
            )
            .accessibilityHidden(true)
    }
}

private extension CGFloat {
    func clamped(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lower), upper)
    }
}
