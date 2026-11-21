import Foundation
import FleetCore

struct WorkloadTraits: Equatable {
    var requiresAppleSilicon = false
    var requiresLocalGUI = false
    var latencySensitive = false
    var requiresDocker = false
    var requiredTools: Set<String> = []
    var memoryBytes: Int64 = 0
}

enum WorkloadCatalogue {
    static func traits(forProcessNamed name: String, memoryBytes: Int64) -> WorkloadTraits {
        var traits = WorkloadTraits()
        traits.memoryBytes = memoryBytes
        let needle = name.lowercased()

        if ["mlx", "heavyweights", "localaivoice", "coreml", "ane"].contains(where: needle.contains) {
            traits.requiresAppleSilicon = true
        }

        if ["claude", "chatgpt", "spotify", "fleetconsole", "windowserver", "windowmanager",
            "finder", "safari", "zed", "iterm", "dock", "tradingview"].contains(where: needle.contains) {
            traits.requiresLocalGUI = true
        }

        if ["codex", "claude", "cursor", "lsp", "language-server", "watchman"]
            .contains(where: needle.contains) {
            traits.latencySensitive = true
        }

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

    static func traits(for record: ServiceRecord) -> WorkloadTraits {
        var traits = self.traits(forProcessNamed: record.commandLine,
                                 memoryBytes: 0)
        traits.requiresLocalGUI = false
        return traits
    }
}

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
    var reasons: [String]

    var summary: String { reasons.joined(separator: " · ") }
}

enum Placement {
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
