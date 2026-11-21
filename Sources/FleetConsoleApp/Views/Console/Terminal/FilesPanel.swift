import SwiftUI

@MainActor
final class FilesPanel: PTYBackedSurface {
    let tool: ConsoleTool = .files

    private let session = PTYSession(refusesBelowMinimum: true)
    private var currentContext = ToolContext()
    private var activated = false
    private var resolvedBinary: URL?

    var cellMetrics: TerminalCellMetrics { session.cell }

    var reservedWidth: CGFloat { session.reservedWidth }

    var isLive: Bool { session.phase == .running }

    func activate(context: ToolContext) {
        let dir = ToolBinary.usableDirectory(context.workingDirectory)
        let binary = ToolBinary.resolve("yazi")
        resolvedBinary = binary

        guard let binary else {
            currentContext = context
            return
        }

        if !activated {
            currentContext = context
            activated = true
            session.ensureRunning(makeLaunch(binary: binary, dir: dir))
            return
        }

        if dir != ToolBinary.usableDirectory(currentContext.workingDirectory) {
            currentContext = context
            session.restart(makeLaunch(binary: binary, dir: dir))
        }
        currentContext = context
    }

    func resize(to grid: TerminalGrid) {
        session.settle(grid)
    }

    func deactivate() {
    }

    func makeView() -> AnyView {
        guard resolvedBinary != nil else {
            return AnyView(
                EmptyPanelView(
                    symbol: "folder",
                    title: "Yazi not found",
                    detail: "Install Yazi (https://yazi-rs.github.io) so the file surface can "
                        + "open. Searched: /opt/homebrew/bin/yazi, ~/.cargo/bin/yazi, "
                        + "$HOME/.local/bin/yazi, and every entry in $PATH."
                )
            )
        }
        return AnyView(
            PTYPanelView(
                session: session,
                tooNarrowDetail: "Yazi's three-pane layout needs at least "
                    + "\(TerminalGrid.minimum.columns) columns to draw honestly. Widen the panel."
            )
            .onAppear {
                if let grid = self.session.proposed {
                    self.session.settle(grid)
                }
            }
        )
    }

    private static var templateDirectory: URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("yazi", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("yazi.toml").path) {
            return bundled
        }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/yazi", isDirectory: true)
        return FileManager.default.fileExists(atPath: source.appendingPathComponent("yazi.toml").path)
            ? source : nil
    }

    private static func configHome(dark: Bool) -> URL? {
        guard let template = templateDirectory else { return nil }
        let fm = FileManager.default
        let variant = dark ? "dark" : "light"

        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.fleetconsole.app/yazi/\(variant)", isDirectory: true)
        guard let base else { return template }

        do {
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
            for name in ["yazi.toml", "init.lua"] {
                try copy(template.appendingPathComponent(name), to: base.appendingPathComponent(name))
            }
            try copy(template.appendingPathComponent("theme-\(variant).toml"),
                     to: base.appendingPathComponent("theme.toml"))
            return base
        } catch {
            return template
        }
    }

    private static var isDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static func copy(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }

    private func makeLaunch(binary: URL, dir: URL) -> PTYSession.Launch {
        var environment = ToolBinary.environment(withSearchPath: true)
        if let configHome = Self.configHome(dark: Self.isDarkAppearance) {
            environment.append("YAZI_CONFIG_HOME=" + configHome.path)
        }

        return PTYSession.Launch(
            executable: binary,
            arguments: [dir.path],
            argv0: nil,
            workingDirectory: dir,
            environment: environment
        )
    }
}
