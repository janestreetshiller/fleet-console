import SwiftUI

// The Yazi file surface.
//
// Design decisions:
//   - `refusesBelowMinimum: true` — Yazi's three-pane layout collapses under
//     40 columns. Below that, PTYSession itself refuses to forward the grid to
//     the child, and PTYPanelView shows the honest "too narrow" state instead.
//   - The binary is resolved at activate time, not at init: the user may install
//     Yazi between flips of the panel, and the panel should pick it up without
//     requiring a relaunch.
//   - When Yazi is absent, `EmptyPanelView` says so with the exact paths
//     searched, so the user knows what to install and where to put it. No silent
//     fallback to a plain shell — the README's "absent binary means the panel
//     says so" rule.
//   - Directory changes restart the child, same as TerminalPanel, because Yazi
//     opens a tree at its argv path and cannot navigate to a different root from
//     inside the TUI.

@MainActor
final class FilesPanel: PTYBackedSurface {
    let tool: ConsoleTool = .files

    private let session = PTYSession(refusesBelowMinimum: true)
    private var currentContext = ToolContext()
    private var activated = false
    private var resolvedBinary: URL?

    // MARK: PTYBackedSurface

    var cellMetrics: TerminalCellMetrics { session.cell }

    var reservedWidth: CGFloat { session.reservedWidth }

    var isLive: Bool { session.phase == .running }

    // MARK: ToolSurface

    func activate(context: ToolContext) {
        let dir = ToolBinary.usableDirectory(context.workingDirectory)
        let binary = ToolBinary.resolve("yazi")
        resolvedBinary = binary

        guard let binary else {
            // Binary not found — makeView() will show the unavailable state.
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
        // Keep warm — Yazi's tree is worth retaining across panel toggles.
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

    // MARK: Private

    /// The panel's own Yazi configuration, shipped in the bundle.
    ///
    /// Without this the panel runs against `~/.config/yazi`, which means the file
    /// surface inside FleetConsole looks like whatever the user's own file
    /// manager looks like and changes when they change it. It also means
    /// inheriting their previewer plugins: this machine's config points two
    /// `prepend_previewers` at `piper`, which is declared in `package.toml` and
    /// not installed, so both previews fail.
    ///
    /// The bundled config is a different thing from a copy of theirs — a
    /// fixed-purpose file *view*: no status line, achromatic, one icon set. See
    /// `Resources/yazi/`.
    private static var templateDirectory: URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("yazi", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("yazi.toml").path) {
            return bundled
        }
        // Running from `swift run` rather than the bundle — the app is developed
        // that way and the panel should look the same there.
        //
        // `Resources/` is a sibling of `Sources/`, not a child of it, so the
        // walk has to reach the package root. Stopping at `Sources` pointed this
        // at `Sources/Resources/yazi`, which does not exist — so `configHome`
        // came back nil, `YAZI_CONFIG_HOME` was never set, and every dev build
        // ran the panel against `~/.config/yazi` instead. That is the exact
        // failure the bundled config exists to prevent: the surface came out in
        // the user's own colour theme rather than achromatic, and inherited
        // their `piper` previewers, which are declared and not installed.
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Terminal
            .deletingLastPathComponent()      // Console
            .deletingLastPathComponent()      // Views
            .deletingLastPathComponent()      // FleetConsoleApp
            .deletingLastPathComponent()      // Sources
            .deletingLastPathComponent()      // package root
            .appendingPathComponent("Resources/yazi", isDirectory: true)
        return FileManager.default.fileExists(atPath: source.appendingPathComponent("yazi.toml").path)
            ? source : nil
    }

    /// `YAZI_CONFIG_HOME` for the current system appearance.
    ///
    /// Yazi reads exactly one `theme.toml` out of its config home, and the panel
    /// background follows the window (`PTYSurface.applyAppearance`), so the theme
    /// has to be chosen at launch rather than shipped as a single file. The
    /// template directory holds `theme-dark.toml` and `theme-light.toml`; this
    /// stages the right one, under its own name, into a per-appearance directory
    /// in Caches.
    ///
    /// Without this the Light Mode panel painted the dark ramp — #C8C9CD text on
    /// a white background, ~1.3:1 — onto a surface that had correctly turned
    /// white underneath it.
    ///
    /// Restaged on every launch. The files are a few KB and staging them fresh
    /// means editing the theme and reopening the panel shows the edit, instead of
    /// a stale copy surviving in Caches until someone works out why.
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
            // Staging failed — fall back to the template directory. Its bundled
            // theme.toml may be absent, in which case Yazi uses its own default
            // theme: coloured, but readable. Never fall through to the user's
            // ~/.config/yazi, which is the case the bundled config exists to
            // prevent.
            return template
        }
    }

    /// The appearance the panel will actually be drawn in. Read from the app
    /// rather than a SwiftUI `colorScheme`, because this is a class that builds
    /// an `execve` environment, not a view — and the child needs the answer
    /// before the view exists.
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
        // Yazi needs $PATH to find its helpers (unar, ffmpeg, …). The full search
        // path is given, same as we resolved the binary with, so those helpers
        // are findable too.
        // `environment` is execve's `KEY=VALUE` vector, not a dictionary.
        var environment = ToolBinary.environment(withSearchPath: true)
        if let configHome = Self.configHome(dark: Self.isDarkAppearance) {
            environment.append("YAZI_CONFIG_HOME=" + configHome.path)
        }

        // Exec Yazi directly — no shell between the panel and the child.
        // The working directory is passed as an argument rather than inherited
        // so that `cd` inside Yazi does not confuse the panel's context.
        return PTYSession.Launch(
            executable: binary,
            arguments: [dir.path],
            argv0: nil,
            workingDirectory: dir,
            environment: environment
        )
    }
}
