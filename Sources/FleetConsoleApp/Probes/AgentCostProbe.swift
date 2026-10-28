import Foundation
import FleetCore

/// Today's agent spend, sampled off the main thread.
///
/// This lives in the app rather than in `fleetd`, and that is a boundary
/// decision rather than a convenience. The controller's job is to own processes;
/// reading another tool's transcripts is neither supervision nor something that
/// needs to survive the app being closed. Putting it here leaves the daemon, the
/// socket protocol and the process-safety rules exactly as they were — which the
/// merge gate for this port requires.
///
/// The scan walks real directories and memory-maps real files, so it never runs
/// on the snapshot cadence: `refresh()` is called freely and the probe itself
/// decides whether enough time has passed. See `minimumInterval`.
@Observable
@MainActor
final class AgentCostProbe {
    private(set) var totals: AgentCostTotals?
    private(set) var scanning = false

    /// A day's transcripts do not change fast enough to be worth re-reading on
    /// every popover open, and a working directory of Claude sessions is large
    /// enough that doing so is visible.
    private let minimumInterval: TimeInterval = 60

    private let queue = DispatchQueue(label: "com.fleetconsole.app.agentcost")
    private var lastScan: Date?

    /// Samples if the last scan has aged out. `force` is for the one case that
    /// is not a cadence — an operator pressing refresh and expecting the number
    /// under their cursor to be the one on disk right now.
    func refresh(force: Bool = false) {
        guard !scanning else { return }
        if !force, let lastScan, Date().timeIntervalSince(lastScan) < minimumInterval { return }
        scanning = true
        queue.async { [weak self] in
            let scanned = AgentCostScanner().scan()
            Task { @MainActor in
                guard let self else { return }
                self.totals = scanned
                self.lastScan = Date()
                self.scanning = false
            }
        }
    }

    /// What one agent cost, or `nil` when it is unknown — which is not the same
    /// as zero, and is why this returns the whole snapshot rather than a Double.
    func snapshot(for agentID: String) -> AgentCostSnapshot? {
        totals?.snapshot(for: agentID)
    }
}
