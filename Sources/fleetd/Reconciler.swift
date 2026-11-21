import Foundation
import FleetCore

enum Reconciler {

    struct Inputs {
        var table: ProcessTable
        var config: FleetConfig
        var services: [ServiceRecord]
        var uid: uid_t = geteuid()
    }

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
                for peer in inputs.table.processes(inGroup: match.pgid) { claimed.insert(peer.pid) }
            }
            result.append(service)
        }
        return (result.sorted { ($0.running ? 0 : 1, $0.name) < ($1.running ? 0 : 1, $1.name) }, claimed)
    }

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

        var portOwners: [Int: ServiceRecord] = [:]
        for service in live {
            for port in service.declaredPorts { portOwners[port] = service }
        }

        var formerByPID: [Int32: String] = [:]
        for service in inputs.services where service.state.isTerminal {
            if let pid = service.pid, let signature = service.startSignature,
               let proc = inputs.table.process(pid), proc.startSignature == signature {
                formerByPID[pid] = service.id
            }
        }

        var found: [String: UnmanagedProcess] = [:]

        func key(for proc: ProcessTable.Proc) -> String {
            "\(proc.pid):\(stableHash(proc.startSignature))"
        }

        for listener in inputs.table.listeners {
            guard listener.uid == inputs.uid else { continue }
            guard let proc = inputs.table.process(listener.pid) else { continue }
            guard !managedPGIDs.contains(proc.pgid), !managedPIDs.contains(proc.pid) else { continue }
            guard !claimedPIDs.contains(proc.pid) else { continue }
            if inputs.config.ignoredPorts.contains(listener.port) { continue }
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

        for proc in inputs.table.byPID.values {
            guard proc.uid == inputs.uid else { continue }
            guard !managedPGIDs.contains(proc.pgid), !managedPIDs.contains(proc.pid) else { continue }
            guard !claimedPIDs.contains(proc.pid) else { continue }
            let id = key(for: proc)
            guard found[id] == nil else { continue }
            guard !shellExecutables.contains(proc.executableName) else { continue }
            let haystack = proc.commandLine.lowercased()
            guard inputs.config.devServerPatterns.contains(where: { haystack.contains($0.lowercased()) }) else { continue }
            if isIgnored(command: proc.executableName, commandLine: proc.commandLine, config: inputs.config) { continue }
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
