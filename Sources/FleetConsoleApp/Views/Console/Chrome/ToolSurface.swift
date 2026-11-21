import SwiftUI

enum ConsoleTool: String, CaseIterable, Identifiable, Sendable {
    case terminal
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .files: return "Files"
        }
    }

    var symbol: String {
        switch self {
        case .terminal: return "terminal"
        case .files: return "folder"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .terminal: return "t"
        case .files: return "f"
        }
    }

    var isPTYBacked: Bool {
        switch self {
        case .terminal, .files: return true
        }
    }
}

struct TerminalCellMetrics: Equatable, Sendable {
    var width: CGFloat
    var height: CGFloat

    static let placeholder = TerminalCellMetrics(width: 7, height: 15)

    var isUsable: Bool { width > 0.5 && height > 0.5 }
}

struct TerminalGrid: Equatable, Sendable {
    var columns: Int
    var rows: Int

    static let minimum = TerminalGrid(columns: 40, rows: 10)

    var fitsMinimum: Bool {
        columns >= Self.minimum.columns && rows >= Self.minimum.rows
    }

    static func fitting(_ size: CGSize,
                        cell: TerminalCellMetrics,
                        reservedWidth: CGFloat = 0) -> TerminalGrid {
        guard cell.isUsable, size.width > 0, size.height > 0 else { return minimum }
        let drawable = max(0, size.width - reservedWidth)
        return TerminalGrid(columns: max(1, Int((drawable / cell.width).rounded(.down))),
                            rows: max(1, Int((size.height / cell.height).rounded(.down))))
    }
}

@MainActor
final class ToolResizeCoalescer {
    private let quietPeriod: Duration
    private var pending: TerminalGrid?
    private var settled: TerminalGrid?
    private var task: Task<Void, Never>?
    private let onSettle: (TerminalGrid) -> Void

    init(quietPeriod: Duration = .milliseconds(120),
         onSettle: @escaping (TerminalGrid) -> Void) {
        self.quietPeriod = quietPeriod
        self.onSettle = onSettle
    }

    func propose(_ grid: TerminalGrid) {
        guard grid != pending else { return }
        pending = grid
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.quietPeriod)
            guard !Task.isCancelled else { return }
            self.flush()
        }
    }

    func flush() {
        task?.cancel()
        task = nil
        guard let grid = pending, grid != settled else { return }
        settled = grid
        onSettle(grid)
    }

    func reset() {
        task?.cancel()
        task = nil
        pending = nil
        settled = nil
    }

    deinit { task?.cancel() }
}

struct ToolContext: Equatable, Sendable {
    var workingDirectory: URL
    var subject: String
    var serviceID: String?

    init(workingDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
         subject: String = "This Mac",
         serviceID: String? = nil) {
        self.workingDirectory = workingDirectory
        self.subject = subject
        self.serviceID = serviceID
    }
}

@MainActor
protocol ToolSurface: AnyObject {
    var tool: ConsoleTool { get }

    var isLive: Bool { get }

    func activate(context: ToolContext)

    func resize(to grid: TerminalGrid)

    func deactivate()

    func makeView() -> AnyView
}

@MainActor
final class ToolSurfaceRegistry {
    private var surfaces: [ConsoleTool: any ToolSurface] = [:]

    func surface(for tool: ConsoleTool) -> any ToolSurface {
        if let existing = surfaces[tool] { return existing }
        let made: any ToolSurface
        switch tool {
        case .terminal: made = TerminalPanel()
        case .files: made = FilesPanel()
        }
        surfaces[tool] = made
        return made
    }

    var live: Set<ConsoleTool> {
        Set(surfaces.filter { $0.value.isLive }.keys)
    }

    func deactivateAll() {
        for surface in surfaces.values { surface.deactivate() }
    }

    func closeTerminalSessions() {
        (surfaces[.terminal] as? TerminalPanel)?.windowClosed()
    }

    func resumeTerminal() {
        (surfaces[.terminal] as? TerminalPanel)?.windowReopened()
    }
}

struct EmptyPanelView: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(ConsoleFont.emptyGlyph)
                .foregroundStyle(SurfaceInk.secondary)
            Text(title)
                .font(ConsoleFont.subtitle.weight(.medium))
                .foregroundStyle(.secondary)
            Text(detail)
                .font(ConsoleFont.caption)
                .foregroundStyle(SurfaceInk.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ConsoleMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum ConsoleToolMetrics {
    static let referenceCell = TerminalCellMetrics(width: 8, height: 16)

    static let scrollerReserve: CGFloat = 17

    static let panelMin: CGFloat = referenceCell.width * CGFloat(TerminalGrid.minimum.columns)
        + scrollerReserve
        + ChromeRailMetrics.handleWidth
    static let panelIdeal: CGFloat = 377
    static let panelMax: CGFloat = 610

    static let toggleSize: CGFloat = 22
    static let railSpacing: CGFloat = 6

    static let reveal = Animation.spring(response: 0.34, dampingFraction: 0.86)
}
