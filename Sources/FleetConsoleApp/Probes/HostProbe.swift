import Foundation
import FleetCore

/// Read-only capability probe for the other machines in the fleet.
///
/// This asks a host what it *is*; it never asks it to do anything. The remote
/// command is a fixed string compiled into the binary — no part of it comes from
/// config, and `Shell.run` passes an argv array rather than a shell string, so
/// there is nothing to inject into. `BatchMode=yes` means a host that would prompt
/// for a password fails immediately instead of hanging a background queue forever.
///
/// The point of collecting this is `Placement`: "you can move this there" is a
/// claim, and this app does not make claims without evidence. Architecture, free
/// memory, disk headroom and link quality are the evidence.

struct LinkQuality: Equatable {
    /// Nil when the path was never measured.
    var direct: Bool?
    var rttMs: Double?
    var via: String?

    var label: String {
        guard let direct else { return "not measured" }
        let rtt = rttMs.map { String(format: "%.0f ms", $0) } ?? "—"
        return direct ? "direct · \(rtt)" : "relayed via \(via ?? "DERP") · \(rtt)"
    }

    /// A relay adds latency *and* jitter. Interactive work is unusable across one
    /// long before throughput becomes the problem.
    var suitsInteractive: Bool {
        guard let direct, let rttMs else { return false }
        return direct && rttMs < 20
    }
}

struct HostCapabilities: Identifiable, Equatable {
    let id: String
    var name: String
    var target: String
    var reachable = false
    var probedAt: Date?
    var error: String?

    var os: String?
    var arch: String?
    var cpuBrand: String?
    var cores: Int?
    var memoryBytes: Int64?
    var diskFreeBytes: Int64?
    var diskUsedPercent: Int?
    var loadOne: Double?
    var tools: Set<String> = []
    var link = LinkQuality()
    var isSelf = false

    /// MLX and Metal compute are Apple-Silicon-only. This is the single fact that
    /// decides most of the interesting placement questions in this fleet.
    var isAppleSilicon: Bool { arch == "arm64" && os == "Darwin" }

    var summary: String {
        guard reachable else { return error ?? "not reachable" }
        var parts: [String] = []
        if let arch { parts.append(arch) }
        if let cores { parts.append("\(cores) cores") }
        if let memoryBytes { parts.append("\(SystemFmt.size(memoryBytes)) RAM") }
        if let diskFreeBytes { parts.append("\(SystemFmt.size(diskFreeBytes)) free") }
        return parts.joined(separator: " · ")
    }
}

/// Everything the probe needs to know, emitted as key=value so parsing cannot be
/// confused by a login banner. Works on both macOS and Linux. File scope so the
/// background probe can read it without crossing the main actor.
private let remoteProbeCommand = """
echo "os=$(uname -s)"; echo "arch=$(uname -m)"; \
echo "cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null)"; \
echo "cpu=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || (grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2))"; \
echo "mem=$(sysctl -n hw.memsize 2>/dev/null || echo $(( $(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null) * 1024 )))"; \
df -k / | awk 'NR==2{print "diskfree="$4; print "diskpct="$5}'; \
echo "load=$(uptime | sed 's/.*average[s]*: *//' | cut -d, -f1 | tr -d ' ')"; \
for t in node python3 uv docker git tmux; do command -v $t >/dev/null && echo "tool=$t"; done
"""

@Observable
@MainActor
final class HostProbe {
    private(set) var hosts: [HostCapabilities] = []
    private(set) var probing = false

    private let queue = DispatchQueue(label: "com.fleetconsole.app.hosts")

    func probe(devices: [DeviceRecord]) {
        guard !probing else { return }
        probing = true
        let aliases = Self.sshAliases()
        let targets = devices.map { device -> (id: String, name: String, host: String,
                                               tailnet: String?, isSelf: Bool) in
            let fallback = device.tailscaleHost ?? device.localHost ?? device.name
            // Prefer an ssh_config alias that points at this device, because the
            // alias carries the User. Probing the tailnet name directly logs in as
            // whoever is running this app, which is usually the wrong account.
            let alias = [device.tailscaleIP, device.tailscaleHost, device.localIP, device.localHost]
                .compactMap { $0 }
                .compactMap { aliases[$0.lowercased()] }
                .first
            // Two different names for the same machine: ssh needs the alias that
            // carries the login, `tailscale ping` needs the tailnet identity and
            // does not know what an ssh_config alias is.
            return (id: device.id, name: device.name, host: alias ?? fallback,
                    tailnet: device.tailscaleIP ?? device.tailscaleHost,
                    isSelf: device.evidence.isSelf)
        }
        queue.async { [weak self] in
            let probed = targets.map { Self.measure(id: $0.id, name: $0.name,
                                                    target: $0.host, tailnet: $0.tailnet,
                                                    isSelf: $0.isSelf) }
            Task { @MainActor in
                guard let self else { return }
                if self.hosts != probed { self.hosts = probed }
                self.probing = false
            }
        }
    }

    /// Maps every `HostName` in `~/.ssh/config` to the first alias that declares it.
    /// Read-only, and only used to pick a login target the user has already set up.
    nonisolated static func sshAliases() -> [String: String] {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config")
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return [:] }

        var mapping: [String: String] = [:]
        var currentAliases: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch parts[0].lowercased() {
            case "host":
                // Wildcards are catch-alls, not a way to reach one machine.
                currentAliases = value.split(separator: " ").map(String.init)
                    .filter { !$0.contains("*") && !$0.contains("?") }
            case "hostname":
                guard let alias = currentAliases.first else { continue }
                let key = value.lowercased()
                if mapping[key] == nil { mapping[key] = alias }
            default:
                continue
            }
        }
        return mapping
    }

    nonisolated private static func measure(id: String, name: String, target: String,
                                            tailnet: String?, isSelf: Bool) -> HostCapabilities {
        var host = HostCapabilities(id: id, name: name, target: target)
        host.isSelf = isSelf
        host.probedAt = Date()

        if isSelf {
            // No point SSHing to ourselves, and it would fail on a machine without
            // Remote Login enabled even though we can read all of this directly.
            host.reachable = true
            host.os = "Darwin"
            host.arch = "arm64"
            host.cpuBrand = Sysctl.string("machdep.cpu.brand_string")
            host.cores = Sysctl.int("hw.logicalcpu")
            host.memoryBytes = Int64(ProcessInfo.processInfo.physicalMemory)
            if let values = try? URL(fileURLWithPath: "/").resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
                host.diskFreeBytes = values.volumeAvailableCapacityForImportantUsage
                if let total = values.volumeTotalCapacity, total > 0,
                   let free = values.volumeAvailableCapacityForImportantUsage {
                    host.diskUsedPercent = Int((1 - Double(free) / Double(total)) * 100)
                }
            }
            var loads = [Double](repeating: 0, count: 3)
            if getloadavg(&loads, 3) == 3 { host.loadOne = loads[0] }
            host.link = LinkQuality(direct: true, rttMs: 0, via: "loopback")
            return host
        }

        let result = Shell.run("/usr/bin/ssh", [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=6",
            "-o", "StrictHostKeyChecking=accept-new",
            target, remoteProbeCommand
        ], timeout: 20)

        guard result.succeeded else {
            host.reachable = false
            host.error = Self.friendlyError(result.stderr)
            host.link = tailnet.map(measureLink) ?? LinkQuality()
            return host
        }

        host.reachable = true
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch parts[0] {
            case "os": host.os = value
            case "arch": host.arch = value
            case "cores": host.cores = Int(value)
            case "cpu": host.cpuBrand = value.isEmpty ? nil : value
            case "mem": host.memoryBytes = Int64(value)
            case "diskfree": host.diskFreeBytes = Int64(value).map { $0 * 1024 }
            case "diskpct": host.diskUsedPercent = Int(value.replacingOccurrences(of: "%", with: ""))
            case "load": host.loadOne = Double(value)
            case "tool": host.tools.insert(value)
            default: break
            }
        }
        host.link = tailnet.map(measureLink) ?? LinkQuality()
        return host
    }

    /// `tailscale ping` is the only thing that distinguishes a direct path from a
    /// relayed one, and that distinction decides whether interactive work can move.
    nonisolated private static func measureLink(_ target: String) -> LinkQuality {
        guard let binary = Shell.which("tailscale", candidates: [
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            "/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale"
        ]) else { return LinkQuality() }

        let result = Shell.run(binary, ["ping", "-c", "3", "--timeout", "3s", target], timeout: 15)
        var quality = LinkQuality()
        var samples: [Double] = []
        for line in result.stdout.split(separator: "\n") where line.contains("pong") {
            quality.direct = !line.contains("via DERP")
            if line.contains("via DERP"),
               let open = line.range(of: "DERP("), let close = line[open.upperBound...].firstIndex(of: ")") {
                quality.via = String(line[open.upperBound..<close])
            }
            if let range = line.range(of: " in "),
               let ms = line[range.upperBound...].split(separator: "m").first,
               let value = Double(ms.trimmingCharacters(in: .whitespaces)) {
                samples.append(value)
            }
        }
        if result.stdout.contains("direct connection not established") { quality.direct = false }
        // The worst sample, not the mean: a path that is sometimes 8 ms and
        // sometimes 125 ms is a 125 ms path for anything interactive.
        quality.rttMs = samples.max()
        return quality
    }

    nonisolated private static func friendlyError(_ stderr: String) -> String {
        let text = stderr.lowercased()
        if text.contains("permission denied") { return "SSH key not accepted" }
        if text.contains("connection timed out") || text.contains("operation timed out") {
            return "connection timed out"
        }
        if text.contains("could not resolve") || text.contains("nodename nor servname") {
            return "hostname does not resolve"
        }
        if text.contains("connection refused") { return "SSH refused — Remote Login may be off" }
        return stderr.split(separator: "\n").first.map(String.init) ?? "probe failed"
    }
}
