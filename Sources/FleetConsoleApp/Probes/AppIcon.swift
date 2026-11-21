import AppKit
import SwiftUI

@MainActor
enum AppIcon {

    static let declaredBundleIdentifiers: [String: String] = [
        "claude": "com.anthropic.claudefordesktop",
        "codex": "com.openai.codex",
        "gemini": "com.google.Gemini",
        "grok": "com.x.grok",
    ]

    static func bundleIdentifier(forTool tool: String) -> String? {
        declaredBundleIdentifiers[tool.lowercased()]
    }

    private static var byBundleIdentifier: [String: NSImage?] = [:]
    private static var byProcess: [String: String?] = [:]

    static func icon(pid: Int32, startSignature: String) -> NSImage? {
        let key = "\(pid):\(startSignature)"
        if let cached = byProcess[key] {
            return cached.flatMap { icon(bundleIdentifier: $0) }
        }
        let identifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        byProcess[key] = identifier
        return identifier.flatMap { icon(bundleIdentifier: $0) }
    }

    static func icon(bundleIdentifier: String) -> NSImage? {
        if let cached = byBundleIdentifier[bundleIdentifier] { return cached }
        let resolved = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        byBundleIdentifier[bundleIdentifier] = resolved
        return resolved
    }

    static func icon(forAgentTool tool: String, pid: Int32, startSignature: String) -> NSImage? {
        if let direct = icon(pid: pid, startSignature: startSignature) { return direct }
        guard let identifier = bundleIdentifier(forTool: tool) else { return nil }
        return icon(bundleIdentifier: identifier)
    }
}

struct AppGlyph: View {
    enum Fallback {
        case tile
        case plain
    }

    let symbol: String
    var fallback: Fallback = .tile
    var tone: StatusTone = .neutral
    var size: CGFloat = 28
    var badge: StatusTone?
    var pid: Int32?
    var startSignature: String?
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
