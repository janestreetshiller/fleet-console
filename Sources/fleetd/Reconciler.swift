import Foundation
import FleetCore

/// Detects processes that are running outside the registry. An agent with shell
/// access can always bypass `fleetctl` — this is the layer that makes the bypass
/// loud rather than preventing it (threat model T4).
enum Reconciler {

    struct Inputs {
        var table: ProcessTable
        var config: FleetConfig
        var services: [ServiceRecord]
        var uid: uid_t = geteuid()
    }

    /// Matches declared local tools against what is actually running. A tool you
    /// declared is never "unmanaged" — you meant it to be there — so it gets a
    /// name, a port and an uptime instead of a warning.
    static func externalServices(_ inputs: Inputs) -> (services: [ExternalService], claimedPIDs: Set<Int32>) {
        var result: [ExternalService] = []
        var claimed: Set<Int32> = []

        for known in inputs.config.knownServices {
            var service = ExternalService(id: known.id,
                                          name: known.name,
                                          symbol: known.symbol ?? "wrench.and.screwdriver",
                                          declaredPorts: known.ports,
                                          url: known.url)
            let needle = known.match.lowercased()

            // Match by command line first, then by any of its declared ports.
            let match = inputs.table.byPID.values.first { proc in
                guard proc.uid == inputs.uid else { return false }
                if !needle.isEmpty, proc.commandLine.lowercased().contains(needle) { return true }
                guard !known.ports.isEmpty else { return false }
                return inputs.table.listeners.contains { $0.pid == proc.pid && known.ports.contains($0.port) }
            }

            if let match {
                service.running = true
                service.pid = match.pid
                service.commandLine = String(match.commandLine.prefix(400))
                service.ports = inputs.table.listeners
                    .filter { $0.pid == match.pid }
                    .map(\.port).sorted()
                service.startedAt = parseStartTime(match.startSignature)
                claimed.insert(match.pid)
                // Children of the tool count as part of it, not as strays.
                for peer in inputs.table.processes(inGroup: match.pgid) { claimed.insert(peer.pid) }
            }
            result.append(service)
        }
        return (result.sorted { ($0.running ? 0 : 1, $0.name) < ($1.running ? 0 : 1, $1.name) }, claimed)
    }

    /// `ps -o lstart` format, e.g. "Sun Jul 27 15:33:49 2026".
    static func parseStartTime(_ signature: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter.date(from: signature.replacingOccurrences(of: "  ", with: " "))
    }

    static func scan(_ inputs: Inputs, claimedPIDs: Set<Int32> = []) -> [UnmanagedProcess] {
        let now = Date()
        let live = inputs.services.filter { !$0.state.isTerminal }
        let managedPGIDs = Set(live.compactMap { $0.pgid })
        let managedPIDs = Set(live.compactMap { $0.pid })

        // Ports that a still-registered service claims. If such a port is held by a
        // process outside its group, the group did not die cleanly.
        var portOwners: [Int: ServiceRecord] = [:]
        for service in live {
            for port in service.declaredPorts { portOwners[port] = service }
        }

        // Processes we launched in the past whose records are terminal: if one of
        // those pids is still alive, we leaked it despite thinking we cleaned up.
        var formerByPID: [Int32: String] = [:]
        for service in inputs.services where service.state.isTerminal {
            if let pid = service.pid, let signature = service.startSignature,
               let proc = inputs.table.process(pid), proc.startSignature == signature {
                formerByPID[pid] = service.id
            }
        }

        var found: [String: UnmanagedProcess] = [:]

        // Identity must survive a controller restart, otherwise "first seen" resets
        // and a process that has been leaking for a day looks brand new. Swift's
        // String.hashValue is seeded per process, so it cannot be used here.
        func key(for proc: ProcessTable.Proc) -> String {
            "\(proc.pid):\(stableHash(proc.startSignature))"
        }

        // 1. Listeners with no registry record.
        for listener in inputs.table.listeners {
            guard listener.uid == inputs.uid else { continue }
            guard let proc = inputs.table.process(listener.pid) else { continue }
            guard !managedPGIDs.contains(proc.pgid), !managedPIDs.contains(proc.pid) else { continue }
            guard !claimedPIDs.contains(proc.pid) else { continue }   // a declared local tool
            if inputs.config.ignoredPorts.contains(listener.port) { continue }
            // Ephemeral-range listeners are short-lived helpers. Flagging them
            // produces an event and an alert for something that is already gone by
            // the time you look — the definition of noise.
            if inputs.config.ephemeralPortFloor > 0,
               listener.port >= inputs.config.ephemeralPortFloor { continue }
            if isIgnored(command: listener.command, commandLine: proc.commandLine, config: inputs.config) { continue }

            let reason: UnmanagedReason
            var formerServiceID = formerByPID[proc.pid]
            if let owner = portOwners[listener.port] {
                reason = .escapedProcessGroup
                formerServiceID = formerServiceID ?? owner.id
            } else {
                reason = .listenerNotInRegistry
            }

            let id = key(for: proc)
            if var existing = found[id] {
                existing.ports = Array(Set(existing.ports + [listener.port])).sorted()
                found[id] = existing
            } else {
                found[id] = UnmanagedProcess(id: id,
                                             pid: proc.pid,
                                             command: listener.command,
                                             commandLine: String(proc.commandLine.prefix(400)),
                                             user: listener.user.isEmpty ? "\(listener.uid)" : listener.user,
                                             ports: [listener.port],
                                             firstSeen: now,
                                             lastSeen: now,
                                             reason: reason,
                                             formerServiceID: formerServiceID)
            }
        }

        // 2. Dev-server-shaped processes that have not (yet) bound a port.
        for proc in inputs.table.byPID.values {
            guard proc.uid == inputs.uid else { continue }
            guard !managedPGIDs.contains(proc.pgid), !managedPIDs.contains(proc.pid) else { continue }
            guard !claimedPIDs.contains(proc.pid) else { continue }   // a declared local tool
            let id = key(for: proc)
            guard found[id] == nil else { continue }
            // A shell whose argv merely *mentions* a dev-server command is not a
            // dev server. Without this, every `zsh -c "… http.server …"` is a
            // false positive, and a noisy unmanaged list is an ignored one.
            guard !shellExecutables.contains(proc.executableName) else { continue }
            let haystack = proc.commandLine.lowercased()
            guard inputs.config.devServerPatterns.contains(where: { haystack.contains($0.lowercased()) }) else { continue }
            if isIgnored(command: proc.executableName, commandLine: proc.commandLine, config: inputs.config) { continue }
            // A process whose parent is also flagged adds noise, not information.
            if let parent = inputs.table.process(proc.ppid), parent.uid == inputs.uid,
               found[key(for: parent)] != nil { continue }

            found[id] = UnmanagedProcess(id: id,
                                         pid: proc.pid,
                                         command: proc.executableName,
                                         commandLine: String(proc.commandLine.prefix(400)),
                                         user: NSUserName(),
                                         ports: [],
                                         firstSeen: now,
                                         lastSeen: now,
                                         reason: formerByPID[proc.pid] != nil ? .escapedProcessGroup : .devServerShape,
                                         formerServiceID: formerByPID[proc.pid])
        }

        return found.values.sorted { ($0.ports.first ?? 0, $0.pid) < ($1.ports.first ?? 0, $1.pid) }
    }

    /// FNV-1a: deterministic across runs, unlike Swift's seeded hashValue.
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 36)
    }

    static let shellExecutables: Set<String> = [
        "zsh", "bash", "sh", "dash", "fish", "tcsh", "csh", "ksh", "login", "script", "env", "xargs",
    ]

    /// Allow-list, not deny-list: an unknown listener always surfaces.
    static func isIgnored(command: String, commandLine: String, config: FleetConfig) -> Bool {
        let name = command.lowercased()
        let line = commandLine.lowercased()
        for ignored in config.ignoredListenerCommands {
            let needle = ignored.lowercased()
            if name == needle || name.hasPrefix(needle) || line.contains("/\(needle)") {
                return true
            }
        }
        return false
    }
}
