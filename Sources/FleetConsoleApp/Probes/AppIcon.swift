import AppKit
import SwiftUI

// Real application icons, where the system can supply one.
//
// A row that says "Claude" over a generic `sparkle` is doing recognition work the
// operating system will do better: you know an app by its icon before you have
// read its name. But an icon is a *claim about identity*, and this app does not
// make claims without evidence — so there are exactly two sources here, both of
// them things macOS already knows, and no third.
//
//   1. **The process is the app.** `NSRunningApplication(processIdentifier:)`
//      answers for anything registered with the window server, and its `icon` is
//      that app's own artwork. This covers Claude.app, ChatGPT.app, Hermes.app,
//      Music.app and every other bundled process in the maps — most of the large
//      tiles on the process map, as it happens.
//
//   2. **A declared mapping to an installed app.** A CLI agent is not a GUI
//      process: `claude` running in a terminal is a Node binary under
//      `~/Library/Application Support/`, it is not registered with the window
//      server, and `NSRunningApplication` returns nil for it. There is no logo
//      on disk to read. What there *may* be is a desktop app for the same tool
//      already installed on this machine, and LaunchServices can find it by
//      bundle identifier — so `Claude Code` borrows `Claude.app`'s icon, and
//      borrows nothing at all when Claude.app is not installed.
//
// What is deliberately absent is a third source: guessing. The `claude` binary
// lives inside `~/Library/Application Support/Claude/claude-code/…`, so the app
// bundle could be *inferred* from the executable path — and that inference is
// right on this machine and wrong on the next one, which is the same argument
// `networkSegments` makes about reading a VLAN tag off the third octet of a
// subnet. The mapping below is a declaration. It is right because someone wrote
// it down, and where nobody has written one down the row keeps its SF Symbol.
//
// No artwork is vendored. Every pixel here belongs to an application already
// installed on this machine, which is also why the icons stay correct when those
// applications are updated and why this file adds nothing to the bundle.

@MainActor
enum AppIcon {

    // MARK: - The declaration
    //
    // Tool name — as `SessionScanner.tools` spells it — to the bundle identifier
    // of the desktop app that shares its identity. Absent from this table, or
    // present and not installed, both mean "no icon", which is a legitimate and
    // common answer: `aider` and `opencode` have no desktop app to borrow from,
    // and an SF Symbol is the honest and native rendering for them.
    //
    // Identifiers are the real ones, read off the running applications rather
    // than assumed from the vendor's name — `ChatGPT.app` reports
    // `com.openai.codex`, which is not what anyone would have guessed.
    /// Tool name → the desktop app whose artwork stands for it.
    ///
    /// Keyed on the **tool name as the sessions carry it**, lowercased, and
    /// looked up through `bundleIdentifier(forTool:)` rather than by subscript.
    /// It used to be keyed on display names — `"Claude Code"`, `"Codex"`,
    /// `"Gemini CLI"` — and every caller subscripted it with `session.tool`,
    /// which is `codex`, `claude`, `orcs`. Not one lookup could ever match, so
    /// every agent everywhere fell through to the generic symbol tile and the
    /// whole `AppGlyph` path was dead on arrival. Two of the four keys were not
    /// even the shape of a tool name: nothing is ever called "Gemini CLI" by
    /// the thing that reports it.
    static let declaredBundleIdentifiers: [String: String] = [
        "claude": "com.anthropic.claudefordesktop",
        "codex": "com.openai.codex",
        "gemini": "com.google.Gemini",
        "grok": "com.x.grok",
    ]

    /// The declared app for a tool, matched without caring about case.
    ///
    /// A tool name arrives from `ps` and from the controller, and those two do
    /// not agree about capitalisation. Case-sensitivity here is not a rule
    /// anyone chose, it is the default behaviour of a dictionary — and it is
    /// what silently disabled this feature.
    static func bundleIdentifier(forTool tool: String) -> String? {
        declaredBundleIdentifiers[tool.lowercased()]
    }

    // MARK: - Cache
    //
    // The process table samples every few seconds and the map draws forty tiles,
    // so an uncached lookup would mean hundreds of LaunchServices round trips a
    // minute for artwork that changes when an app is updated and at no other
    // time. Icons are cached by bundle identifier — the thing that is actually
    // stable — and the negative answer is cached too, because "this tool has no
    // desktop app" is the common case and is just as expensive to re-derive.

    private static var byBundleIdentifier: [String: NSImage?] = [:]
    /// pid → bundle identifier, keyed with the process's start signature.
    ///
    /// The signature is not decoration. Pids are recycled, and a cache keyed on
    /// the number alone would hand a dead app's icon to whatever inherited its
    /// pid — the same failure the controller refuses to make when it signals a
    /// process, applied to the far less serious business of drawing a picture.
    private static var byProcess: [String: String?] = [:]

    // MARK: - Lookup

    /// The icon for a running process, or nil when the system has none.
    ///
    /// `startSignature` is `ps -o lstart` for the pid, which every row in this
    /// app already carries for exactly this reason.
    static func icon(pid: Int32, startSignature: String) -> NSImage? {
        let key = "\(pid):\(startSignature)"
        if let cached = byProcess[key] {
            return cached.flatMap { icon(bundleIdentifier: $0) }
        }
        let identifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        byProcess[key] = identifier
        return identifier.flatMap { icon(bundleIdentifier: $0) }
    }

    /// The icon of an installed application, by bundle identifier.
    static func icon(bundleIdentifier: String) -> NSImage? {
        if let cached = byBundleIdentifier[bundleIdentifier] { return cached }
        let resolved = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        byBundleIdentifier[bundleIdentifier] = resolved
        return resolved
    }

    /// The icon for a detected agent session.
    ///
    /// The session's own pid first — a tool *could* be a GUI app on some machine
    /// — and the declared mapping second. Both can miss, and missing is fine.
    static func icon(forAgentTool tool: String, pid: Int32, startSignature: String) -> NSImage? {
        if let direct = icon(pid: pid, startSignature: startSignature) { return direct }
        guard let identifier = bundleIdentifier(forTool: tool) else { return nil }
        return icon(bundleIdentifier: identifier)
    }
}

// MARK: - View

/// An entity's icon: the application's own artwork when macOS has it, and the
/// existing `EntityIcon` symbol tile when it does not.
///
/// The two are the same size and sit on the same baseline, so a list mixing
/// bundled apps and CLI processes does not go ragged — which is most lists in
/// this app.
///
/// **On colour.** The design system says colour is a status vocabulary, and an
/// app icon is full-colour by definition. It is not a violation for the same
/// reason a VLAN tag is `.neutral`: this is *identity*, which has no good/bad
/// axis, and it is drawn in a channel status never uses. The status tone still
/// arrives where it always did — the badge, the row's text, the tile's fill — so
/// nothing that was legible without colour becomes dependent on it. An icon that
/// is missing costs the row nothing, because the symbol tile behind it carries
/// the tone exactly as before.
struct AppGlyph: View {
    /// How the *fallback* draws. A real icon is always itself.
    ///
    /// Both are needed because the app already has both, and swapping one for
    /// the other would be a visible regression rather than a refinement: rows in
    /// the popover carry a tinted `EntityIcon` tile, while a table cell carries a
    /// bare secondary-coloured symbol at text weight. A table that suddenly grew
    /// forty tinted tiles would be a different table.
    enum Fallback {
        /// `EntityIcon` — the tinted, rounded tile used in lists and headers.
        case tile
        /// A bare SF Symbol at the size given, as table cells and compact rows
        /// have always drawn it.
        case plain
    }

    /// The fallback symbol, used whenever no real icon resolves.
    let symbol: String
    var fallback: Fallback = .tile
    var tone: StatusTone = .neutral
    var size: CGFloat = 28
    var badge: StatusTone?
    /// The running process this glyph stands for, if it is one.
    var pid: Int32?
    var startSignature: String?
    /// A tool name from `AppIcon.declaredBundleIdentifiers`, for CLI agents.
    var agentTool: String?

    private var resolved: NSImage? {
        if let agentTool, let pid, let startSignature {
            return AppIcon.icon(forAgentTool: agentTool, pid: pid, startSignature: startSignature)
        }
        if let pid, let startSignature {
            return AppIcon.icon(pid: pid, startSignature: startSignature)
        }
        if let agentTool, let identifier = AppIcon.bundleIdentifier(forTool: agentTool) {
            return AppIcon.icon(bundleIdentifier: identifier)
        }
        return nil
    }

    var body: some View {
        if let resolved {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: resolved)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .accessibilityHidden(true)
                if let badge {
                    StatusBadge(tone: badge, size: size)
                }
            }
        } else {
            switch fallback {
            case .tile:
                EntityIcon(symbol: symbol, tone: tone, size: size, badge: badge)
            case .plain:
                Image(systemName: symbol)
                    .font(ConsoleFont.caption)
                    .foregroundStyle(tone == .neutral ? AnyShapeStyle(.secondary)
                                                      : AnyShapeStyle(tone.ink))
                    .frame(width: size, height: size)
                    .accessibilityHidden(true)
            }
        }
    }
}
