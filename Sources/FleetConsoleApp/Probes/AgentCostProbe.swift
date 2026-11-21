import Foundation
import FleetCore

@Observable
@MainActor
final class AgentCostProbe {
    private(set) var totals: AgentCostTotals?
    private(set) var scanning = false

    private let minimumInterval: TimeInterval = 60

    private let queue = DispatchQueue(label: "com.fleetconsole.app.agentcost")
    private var lastScan: Date?

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

    func snapshot(for agentID: String) -> AgentCostSnapshot? {
        totals?.snapshot(for: agentID)
    }
}
