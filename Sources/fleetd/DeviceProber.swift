import Foundation
import FleetCore

/// Reachability probes for the machines you care about. Three independent pillars
/// (ICMP, TCP, Tailscale's own view) so the UI never has to guess what "online" means.
enum DeviceProber {

    static func probeAll(config: FleetConfig,
                         tailscale: TailscaleStatus?,
                         previous: [String: DeviceRecord]) -> [DeviceRecord] {
        config.devices.map { probe($0, tailscale: tailscale, previous: previous[$0.id]) }
    }

    static func probe(_ device: FleetConfig.DeviceConfig,
                      tailscale: TailscaleStatus?,
                      previous: DeviceRecord?) -> DeviceRecord {
        var record = DeviceRecord(id: device.id,
                                  name: device.name,
                                  model: device.model,
                                  localHost: device.localHost,
                                  tailscaleHost: device.tailscaleHost,
                                  probePort: device.probePort,
                                  lastReachableAt: previous?.lastReachableAt)

        var evidence = DeviceEvidence(checkedAt: Date(), isSelf: device.isSelf)

        if let host = device.tailscaleHost, let status = tailscale, let node = status.node(matching: host) {
            record.tailscaleIP = node.ipv4
            record.tailscaleHost = node.shortName
            evidence.tailscaleOnline = node.online
            evidence.tailscaleLastSeen = node.lastSeen
        } else if let status = tailscale, device.isSelf, let selfNode = status.selfNode {
            record.tailscaleIP = selfNode.ipv4
            record.tailscaleHost = selfNode.shortName
            evidence.tailscaleOnline = selfNode.online
        }

        if device.isSelf {
            // No point pinging ourselves: presence of this process is the evidence.
            record.metrics = SessionScanner.localMetrics()
            record.localIP = primaryLocalIPv4()
            evidence.icmpOK = true
            evidence.icmpRTTms = 0
            record.evidence = evidence
            record.lastReachableAt = Date()
            return record
        }

        let target = record.tailscaleIP ?? device.localHost ?? device.tailscaleHost
        if let target, !target.isEmpty {
            let icmp = ping(target)
            evidence.icmpOK = icmp.ok
            evidence.icmpRTTms = icmp.rttMs
            if let port = device.probePort {
                let outcome = HealthChecker.tcpConnect(host: target, port: port, timeout: 2)
                evidence.tcpOK = outcome.passed
                evidence.tcpPort = port
            }
        }

        record.evidence = evidence
        if evidence.reachable == true { record.lastReachableAt = Date() }

        if evidence.reachable == true, let host = device.sshHost ?? target, !device.isSelf {
            record.metrics = SessionScanner.remoteMetrics(sshHost: host)
        }
        // Two independent sources for the same column, both read-only and both
        // opt-in: that machine's own controller (`remoteQuery`, needs fleetctl
        // installed there) and services declared here and matched over SSH
        // (`services`, needs nothing installed there). A host can use either or
        // both — intel runs a Buzz relay and an opencode server and has no
        // fleetctl, which is precisely the case the second one exists for.
        if evidence.reachable == true {
            var services: [ServiceRecord] = []
            var errors: [String] = []

            if device.remoteQuery {
                let outcome = fetchRemoteServices(device: device, target: target)
                services += outcome.services
                if let error = outcome.error { errors.append(error) }
            }
            if !device.services.isEmpty {
                let outcome = fetchDeclaredServices(device: device, target: target)
                services += outcome.services
                if let error = outcome.error { errors.append(error) }
            }

            if device.remoteQuery || !device.services.isEmpty {
                record.remoteServices = services
                record.remoteError = errors.isEmpty ? nil : errors.joined(separator: "; ")
                record.remoteCheckedAt = Date()
            }
        }
        return record
    }

    /// Multi-device, read-only, over SSH.
    ///
    /// The obvious design — have each controller listen on the tailnet — is
    /// deliberately rejected: "no network listener, ever" is what makes the local
    /// socket's peer-uid check sufficient, and it is the reason there is nothing to
    /// scan or reach from another host. So instead we *shell out* to the other
    /// machine's own fleetctl over the SSH trust you already have, read its JSON,
    /// and render it as read-only. FleetConsole never controls a remote process.
    static func fetchRemoteServices(device: FleetConfig.DeviceConfig,
                                    target: String?) -> (services: [ServiceRecord], error: String?) {
        guard let host = device.sshHost ?? target else {
            return ([], "no ssh host configured")
        }
        let remoteCommand = device.remoteFleetctl ?? "fleetctl"
        let result = Shell.run("/usr/bin/ssh",
                               ["-o", "BatchMode=yes",           // never prompt for a password
                                "-o", "ConnectTimeout=4",
                                "-o", "StrictHostKeyChecking=accept-new",
                                host, "\(remoteCommand) list --json"],
                               timeout: 12)
        guard result.succeeded else {
            let message = result.stderr
                .split(separator: "\n").first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? "ssh failed (status \(result.status))"
            return ([], message)
        }
        guard let data = result.stdout.data(using: .utf8),
              let snapshot = try? Codec.decode(Snapshot.self, from: data) else {
            return ([], "could not parse the remote snapshot")
        }
        // Cap what a remote machine can put into our snapshot.
        return (Array(snapshot.activeServices.prefix(25)), nil)
    }

    /// Declared services on another machine, matched over SSH.
    ///
    /// One round trip per device, not one per service: the remote dumps its
    /// process table and its listener table once, and the matching happens here
    /// in Swift against the same rule `Reconciler.externalServices` uses for the
    /// local machine — command-line substring first, declared port second. Two
    /// declared services on one host cost one `ssh`.
    ///
    /// Everything it produces is `claimed`. That is not a label: it is the flag
    /// every signal path in `Controller` consults, so a record describing a
    /// process on another machine cannot be stopped, restarted or reaped from
    /// here even by a future caller that forgets these are remote. The rule the
    /// app already had — the controller signals only what it started — turns out
    /// to be exactly the rule remote services need.
    static func fetchDeclaredServices(device: FleetConfig.DeviceConfig,
                                      target: String?) -> (services: [ServiceRecord], error: String?) {
        guard !device.services.isEmpty else { return ([], nil) }
        guard let host = device.sshHost ?? target else { return ([], "no ssh host configured") }

        // `lsof` is run without -u: the declared service may belong to a
        // different account on that machine than the one we log in as, and a
        // listener we cannot attribute is still a listener we can report.
        // Failures inside the remote command are swallowed there rather than
        // failing the whole probe — a machine without lsof still gets its
        // process table read.
        let remote = "ps -axww -o pid=,pgid=,lstart=,args= 2>/dev/null; "
            + "echo '\(Self.sectionMarker)'; "
            + "lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $2, $9}'"
        let result = Shell.run("/usr/bin/ssh",
                               ["-o", "BatchMode=yes",
                                "-o", "ConnectTimeout=4",
                                "-o", "StrictHostKeyChecking=accept-new",
                                host, remote],
                               timeout: 15)
        guard result.succeeded else {
            let message = result.stderr
                .split(separator: "\n").first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? "ssh failed (status \(result.status))"
            return ([], message)
        }

        // Split on the **last** marker, not the first.
        //
        // The probe sees itself: the remote `zsh -c …` running this very command
        // is in the process table it dumps, and its argv contains the marker
        // verbatim. Splitting on the first occurrence therefore cut the output
        // inside the `ps` section — the real ports section ended up buried in
        // the tail with a few hundred process lines in front of it, and every
        // declared service came back with no ports at all. It looked like `lsof`
        // had failed remotely; nothing had failed but the parse.
        //
        // Any marker has this problem, including a random nonce, because the
        // marker is always part of the command that gets listed. The last
        // occurrence is the `echo`, always — so that is the seam.
        let marker = Self.sectionMarker
        let processText: String
        let portText: String
        if let range = result.stdout.range(of: marker, options: .backwards) {
            processText = String(result.stdout[..<range.lowerBound])
            portText = String(result.stdout[range.upperBound...])
        } else {
            processText = result.stdout
            portText = ""
        }
        let processes = parseRemoteProcesses(processText)
        let ports = parseRemotePorts(portText)

        var records: [ServiceRecord] = []
        for declared in device.services {
            let needle = declared.match.lowercased()
            let match = processes.first { proc in
                if !needle.isEmpty, proc.commandLine.lowercased().contains(needle) { return true }
                guard !declared.ports.isEmpty else { return false }
                return (ports[proc.pid] ?? []).contains { declared.ports.contains($0) }
            }
            records.append(remoteRecord(declared: declared, device: device,
                                        match: match, ports: match.map { ports[$0.pid] ?? [] } ?? []))
        }
        return (records, nil)
    }

    /// Separates the process table from the listener table in one round trip.
    /// See `fetchDeclaredServices` for why it is matched from the end.
    private static let sectionMarker = "---FLEET-PORTS---"

    private struct RemoteProcess {
        var pid: Int32
        var pgid: Int32
        var startSignature: String
        var commandLine: String
    }

    /// `pid pgid <lstart, 5 fields> args…`. `lstart` is a fixed five-token date
    /// in the C locale, which is what makes this splittable without a regex.
    private static func parseRemoteProcesses(_ text: String) -> [RemoteProcess] {
        var result: [RemoteProcess] = []
        for line in text.split(separator: "\n") {
            // Skip the probe's own shell. Its argv contains the marker and the
            // whole remote command, so it can otherwise satisfy a declared
            // `match` by quoting it — a service would appear "running" on the
            // evidence of us having asked whether it was running.
            guard !line.contains(Self.sectionMarker) else { continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count > 8, let pid = Int32(fields[0]), let pgid = Int32(fields[1]) else { continue }
            let signature = fields[2...6].joined(separator: " ")
            let args = fields[7...].joined(separator: " ")
            result.append(RemoteProcess(pid: pid, pgid: pgid,
                                        startSignature: signature,
                                        commandLine: String(args.prefix(400))))
        }
        return result
    }

    private static func parseRemotePorts(_ text: String) -> [Int32: [Int]] {
        var result: [Int32: [Int]] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2, let pid = Int32(fields[0]),
                  let port = Int(fields[1].split(separator: ":").last ?? "") else { continue }
            result[pid, default: []].append(port)
        }
        return result.mapValues { Array(Set($0)).sorted() }
    }

    /// A declared remote service as a `ServiceRecord`, so it renders through the
    /// same inspector, the same evidence chips and the same row primitives as
    /// everything else. A service that is declared and *not* running still
    /// produces a record — absent from the list would be indistinguishable from
    /// "not declared", and the whole point of declaring it is to notice when it
    /// stops.
    private static func remoteRecord(declared: FleetConfig.KnownService,
                                     device: FleetConfig.DeviceConfig,
                                     match: RemoteProcess?,
                                     ports: [Int]) -> ServiceRecord {
        var record = ServiceRecord(
            id: "remote:\(device.id):\(declared.id)",
            friendlyName: declared.name,
            ownerAgent: device.name,
            purpose: "declared remote service on \(device.name)",
            command: match.map { $0.commandLine.split(separator: " ").map(String.init) } ?? [],
            cwd: "",
            pid: match?.pid,
            pgid: match?.pgid,
            startSignature: match?.startSignature,
            declaredPorts: declared.ports,
            startedAt: match.flatMap { Reconciler.parseStartTime($0.startSignature) } ?? Date(),
            leaseExpiresAt: .distantFuture,
            leaseTTLSec: 0,
            state: match == nil ? .stopped : .running,
            evidence: Evidence(processExists: match != nil,
                               listeningPorts: ports,
                               portScanRan: true,
                               checkedAt: Date()))
        // Read-only across the mesh, enforced by the same flag a local claim uses.
        record.claimed = true
        record.claimedAt = Date()
        return record
    }

    /// Uses /sbin/ping rather than a raw ICMP socket: no entitlement, no privilege.
    static func ping(_ host: String, timeoutSec: Int = 2) -> (ok: Bool, rttMs: Double?) {
        let result = Shell.run("/sbin/ping", ["-c", "1", "-W", "1200", "-t", "\(timeoutSec)", "-n", "-q", host],
                               timeout: TimeInterval(timeoutSec) + 2)
        guard result.succeeded else { return (false, nil) }
        // round-trip min/avg/max/stddev = 1.234/1.234/1.234/0.000 ms
        guard let line = result.stdout.split(separator: "\n").first(where: { $0.contains("round-trip") }),
              let stats = line.split(separator: "=").last?.trimmingCharacters(in: .whitespaces),
              let avg = stats.split(separator: "/").dropFirst().first,
              let value = Double(avg) else {
            return (true, nil)
        }
        return (true, value)
    }

    static func primaryLocalIPv4() -> String? {
        var addresses: [String: String] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: current.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(nulTerminated: host)
            if ip.hasPrefix("127.") { continue }
            addresses[name] = ip
        }
        // Prefer wired, then Wi-Fi, then anything that is not the tailnet interface.
        for candidate in ["en0", "en1", "en2"] {
            if let ip = addresses[candidate], !ip.hasPrefix("100.") { return ip }
        }
        return addresses.first(where: { !$0.value.hasPrefix("100.") })?.value ?? addresses.first?.value
    }
}
