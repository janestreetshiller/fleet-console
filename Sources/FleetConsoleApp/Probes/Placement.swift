import Foundation
import FleetCore

/// Where should this run — answered with reasons, or not answered at all.
///
/// This is the same rule the rest of the app lives by, applied to placement
/// instead of health. "You can move this" is a claim. It requires evidence:
/// a compatible architecture, a host that has been probed recently enough to
/// believe, enough free memory, and a link good enough for how the thing is used.
/// Where the evidence is missing the verdict is `unknown`, not `yes`.
///
/// The rules are deliberately blunt and few. A placement advisor that scores
/// hosts on a continuous fitness function produces confident-looking numbers no
/// one can audit; a short list of hard constraints produces answers you can argue
/// with, which is what you actually want before moving a workload.

// MARK: - What a workload needs

struct WorkloadTraits: Equatable {
    /// MLX and Metal compute do not exist off Apple Silicon. Not a preference.
    var requiresAppleSilicon = false
    /// Has a window. Moving it to a headless box is meaningless.
    var requiresLocalGUI = false
    /// Chatty against the working tree — language servers, file watchers, agents
    /// editing code. Latency and jitter matter far more than throughput.
    var latencySensitive = false
    /// Needs a container runtime on the target.
    var requiresDocker = false
    /// Runtimes that must exist on the host.
    var requiredTools: Set<String> = []
    /// Rough resident footprint, used to check the target has room.
    var memoryBytes: Int64 = 0
}

/// Classifies a running process group by name.
///
/// A catalogue rather than a heuristic, for the same reason the reclaim scanner
/// is one: guessing from a process name is how you tell someone they can move
/// their inference server onto a machine that cannot run it.
enum WorkloadCatalogue {
    static func traits(forProcessNamed name: String, memoryBytes: Int64) -> WorkloadTraits {
        var traits = WorkloadTraits()
        traits.memoryBytes = memoryBytes
        let needle = name.lowercased()

        // Apple-Silicon-only compute.
        if ["mlx", "heavyweights", "localaivoice", "coreml", "ane"].contains(where: needle.contains) {
            traits.requiresAppleSilicon = true
        }

        // Things with a window.
        if ["claude", "chatgpt", "spotify", "fleetconsole", "windowserver", "windowmanager",
            "finder", "safari", "zed", "iterm", "dock", "tradingview"].contains(where: needle.contains) {
            traits.requiresLocalGUI = true
        }

        // Coding agents and editors: they live against your working tree.
        if ["codex", "claude", "cursor", "lsp", "language-server", "watchman"]
            .contains(where: needle.contains) {
            traits.latencySensitive = true
        }

        // Headless runtimes that move well.
        if ["node", "npm", "pnpm", "yarn", "bun", "deno"].contains(where: needle.contains) {
            traits.requiredTools.insert("node")
        }
        if ["python", "uv", "uvicorn", "gunicorn"].contains(where: needle.contains) {
            traits.requiredTools.insert("python3")
        }
        if ["docker", "orbstack", "container"].contains(where: needle.contains) {
            traits.requiresDocker = true
        }
        return traits
    }

    /// A managed service is classified from the argv the controller recorded,
    /// which is better evidence than a process name.
    static func traits(for record: ServiceRecord) -> WorkloadTraits {
        var traits = self.traits(forProcessNamed: record.commandLine,
                                 memoryBytes: 0)
        // A service the controller supervises is by definition headless — it was
        // launched with an argv and a health check, not a window.
        traits.requiresLocalGUI = false
        return traits
    }
}

// MARK: - Verdict

struct PlacementVerdict: Equatable {
    enum Outcome: Equatable {
        case fits
        case blocked
        case unknown

        var tone: StatusTone {
            switch self {
            case .fits: return .good
            case .blocked: return .bad
            case .unknown: return .unknown
            }
        }

        var label: String {
            switch self {
            case .fits: return "can move"
            case .blocked: return "stays"
            case .unknown: return "unknown"
            }
        }
    }

    var outcome: Outcome
    /// Why. Always populated — a verdict with no reason is not a verdict.
    var reasons: [String]

    var summary: String { reasons.joined(separator: " · ") }
}

enum Placement {
    /// Evaluates one workload against one host.
    ///
    /// Order matters: hard architectural blocks are reported before soft ones, so
    /// the first reason you read is the one that actually decides it.
    static func evaluate(_ traits: WorkloadTraits, on host: HostCapabilities) -> PlacementVerdict {
        if host.isSelf {
            return PlacementVerdict(outcome: .fits, reasons: ["already here"])
        }
        guard host.reachable else {
            return PlacementVerdict(outcome: .unknown,
                                    reasons: [host.error ?? "host has not been probed"])
        }
        guard host.arch != nil else {
            return PlacementVerdict(outcome: .unknown, reasons: ["host capabilities unknown"])
        }

        var blockers: [String] = []
        var notes: [String] = []

        if traits.requiresLocalGUI {
            blockers.append("needs a display on this machine")
        }
        if traits.requiresAppleSilicon && !host.isAppleSilicon {
            blockers.append("needs Apple Silicon — \(host.name) is \(host.arch ?? "not arm64")")
        }
        if traits.latencySensitive && !host.link.suitsInteractive {
            blockers.append("works against your files — link is \(host.link.label)")
        }
        for tool in traits.requiredTools.sorted() where !host.tools.contains(tool) {
            blockers.append("\(tool) not installed on \(host.name)")
        }
        if traits.requiresDocker && !host.tools.contains("docker") {
            blockers.append("docker not installed on \(host.name)")
        }
        if traits.memoryBytes > 0, let hostMemory = host.memoryBytes,
           traits.memoryBytes > hostMemory / 2 {
            blockers.append("needs \(SystemFmt.size(traits.memoryBytes)) — over half of \(host.name)'s RAM")
        }

        guard blockers.isEmpty else {
            return PlacementVerdict(outcome: .blocked, reasons: blockers)
        }

        if let free = host.diskFreeBytes { notes.append("\(SystemFmt.size(free)) free there") }
        if let load = host.loadOne { notes.append(String(format: "load %.1f", load)) }
        if traits.memoryBytes > 0 { notes.append("frees \(SystemFmt.size(traits.memoryBytes)) here") }
        if notes.isEmpty { notes.append("no blocking constraint") }
        return PlacementVerdict(outcome: .fits, reasons: notes)
    }
}
