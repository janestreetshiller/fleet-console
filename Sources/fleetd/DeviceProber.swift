import Foundation
import FleetCore

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

    static func fetchRemoteServices(device: FleetConfig.DeviceConfig,
                                    target: String?) -> (services: [ServiceRecord], error: String?) {
        guard let host = device.sshHost ?? target else {
            return ([], "no ssh host configured")
        }
        let remoteCommand = device.remoteFleetctl ?? "fleetctl"
        let result = Shell.run("/usr/bin/ssh",
                               ["-o", "BatchMode=yes",
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
        return (Array(snapshot.activeServices.prefix(25)), nil)
    }

    static func fetchDeclaredServices(device: FleetConfig.DeviceConfig,
                                      target: String?) -> (services: [ServiceRecord], error: String?) {
        guard !device.services.isEmpty else { return ([], nil) }
        guard let host = device.sshHost ?? target else { return ([], "no ssh host configured") }

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

    private static let sectionMarker = "---FLEET-PORTS---"

    private struct RemoteProcess {
        var pid: Int32
        var pgid: Int32
        var startSignature: String
        var commandLine: String
    }

    private static func parseRemoteProcesses(_ text: String) -> [RemoteProcess] {
        var result: [RemoteProcess] = []
        for line in text.split(separator: "\n") {
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
        record.claimed = true
        record.claimedAt = Date()
        return record
    }

    static func ping(_ host: String, timeoutSec: Int = 2) -> (ok: Bool, rttMs: Double?) {
        let result = Shell.run("/sbin/ping", ["-c", "1", "-W", "1200", "-t", "\(timeoutSec)", "-n", "-q", host],
                               timeout: TimeInterval(timeoutSec) + 2)
        guard result.succeeded else { return (false, nil) }
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
        for candidate in ["en0", "en1", "en2"] {
            if let ip = addresses[candidate], !ip.hasPrefix("100.") { return ip }
        }
        return addresses.first(where: { !$0.value.hasPrefix("100.") })?.value ?? addresses.first?.value
    }
}
