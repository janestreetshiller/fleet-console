import Foundation
import AppKit
import FleetCore

// The verbs on the network surface.
//
// Everything here is read-only or clipboard-only. FleetConsole does not
// reconfigure a network, the same way it does not signal a process it did not
// start — `ping` and `traceroute` observe a path, they do not change one.
//
// Both diagnostics run off the main actor with a hard timeout, because a
// traceroute to an unreachable gateway takes as long as its own patience and a
// menu that hangs while it waits is not a menu.

@Observable
@MainActor
final class NetworkActions {
    /// The most recent diagnostic, so the row can show a result in place instead
    /// of opening a window or a modal for four lines of text.
    struct Outcome: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var output: String
        var succeeded: Bool
        var finishedAt = Date()
    }

    private(set) var running: String?
    private(set) var lastOutcome: Outcome?

    var isRunning: Bool { running != nil }

    // MARK: - Clipboard

    /// One place, so "Copy" means the same thing on every row and the
    /// confirmation feedback cannot drift between them.
    @discardableResult
    func copy(_ value: String, label: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        lastOutcome = Outcome(title: "Copied \(label)", output: trimmed, succeeded: true)
        return true
    }

    // MARK: - Diagnostics

    /// Four probes, two-second deadline each, hard-capped by `Shell.run`. Enough
    /// to tell "the gateway answers" from "it does not"; not a latency study.
    func pingGateway(_ address: String) {
        run(title: "ping \(address)", tool: "/sbin/ping",
            arguments: ["-c", "4", "-t", "6", address], timeout: 12)
    }

    /// `-n` skips reverse DNS on every hop, which is most of what makes an
    /// interactive traceroute feel stuck. `-w 1 -q 1 -m 12` keeps the worst case
    /// bounded: twelve hops, one probe each, one second of patience.
    func traceroute(_ address: String) {
        run(title: "traceroute \(address)", tool: "/usr/sbin/traceroute",
            arguments: ["-n", "-w", "1", "-q", "1", "-m", "12", address], timeout: 25)
    }

    func clearOutcome() { lastOutcome = nil }

    #if FLEET_SURFACE_RENDERER
    /// Seeds an outcome so the surface sheet can capture the diagnostic panel.
    /// Compiled only into the renderer, never into the signed bundle.
    func previewOutcome(title: String, output: String) {
        lastOutcome = Outcome(title: title, output: output, succeeded: true)
    }
    #endif

    private func run(title: String, tool: String, arguments: [String], timeout: TimeInterval) {
        guard running == nil else { return }
        running = title
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Shell.run(tool, arguments, timeout: timeout)
            let text = result.stdout.isEmpty ? result.stderr : result.stdout
            Task { @MainActor in
                self.running = nil
                self.lastOutcome = Outcome(
                    title: title,
                    output: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    succeeded: result.succeeded)
            }
        }
    }
}

// MARK: - Support bundle

/// A copyable snapshot of the network picture, sanitised.
///
/// The bundle is a serialisation of the model the screen already renders — the
/// probe structs are `Codable` precisely so this is an encoding rather than a
/// second implementation that can drift from what you were looking at.
///
/// **What is masked and why.** A support bundle is a thing you paste into a chat
/// with someone you are asking for help, so the threat it has to survive is
/// ordinary carelessness rather than an attacker. Two rules:
///
///   * **Addresses.** Private addresses (RFC 1918, link-local, CGNAT/Tailscale)
///     are kept, because they describe your topology and are the entire reason
///     to send the thing. Anything else is a public address that identifies where
///     you are, and is replaced with its family — `‹public IPv4›`.
///   * **Names and secrets.** The Wi-Fi SSID is a location fingerprint and is
///     masked. Nothing in this bundle reads a key, a token or a password from
///     anywhere: there is no field for one, and the assembler below cannot reach
///     the config file, the keychain or the registry. The one credential-shaped
///     thing the app knows about — a VLAN source's controller token — is not
///     part of `NetworkSegment` for exactly this reason.
enum SupportBundle {

    struct Payload: Codable {
        var generatedAt: Date
        var host: String
        var macOS: String
        var routing: RoutingStatus
        var wifi: WiFiSummary
        var vpn: VPNSummary
        var vlanSource: String?
        var segments: [NetworkSegment]

        struct WiFiSummary: Codable {
            var interface: String?
            var poweredOn: Bool
            var connected: Bool
            var ssid: String?
            var rssiDbm: Int?
            var channel: String?
            var transmitRateMbps: Double?
        }

        struct VPNSummary: Codable {
            var configuredCount: Int
            var connectedService: String?
            var tunnelInterfaces: [String]
        }
    }

    /// Builds the payload from live model values and returns it as pretty JSON.
    static func json(routing: RoutingStatus,
                     wifi: WiFiStatus,
                     vpn: VPNStatus,
                     vlanSourceName: String?,
                     segments: [NetworkSegment]) -> String {
        let payload = Payload(
            generatedAt: Date(),
            host: ProcessInfo.processInfo.hostName,
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            routing: sanitise(routing),
            wifi: .init(interface: wifi.interface,
                        poweredOn: wifi.poweredOn,
                        connected: wifi.connected,
                        // Associated-or-not is the diagnostic fact; *which*
                        // network is a location fingerprint.
                        ssid: wifi.ssid == nil ? nil : "‹ssid›",
                        rssiDbm: wifi.rssi,
                        channel: wifi.channel,
                        transmitRateMbps: wifi.transmitRateMbps),
            vpn: .init(configuredCount: vpn.services.count,
                       connectedService: vpn.connectedService?.name,
                       tunnelInterfaces: vpn.tunnels.map(\.interface)),
            vlanSource: vlanSourceName,
            segments: segments.map(sanitise))
        do {
            return String(decoding: try Codec.prettyEncoder.encode(payload), as: UTF8.self)
        } catch {
            return "support bundle could not be encoded: \(error.localizedDescription)"
        }
    }

    static func mask(_ address: String) -> String {
        guard !address.isEmpty else { return address }
        if Subnet.isPrivate(address) { return address }
        return address.contains(":") ? "‹public IPv6›" : "‹public IPv4›"
    }

    private static func sanitise(_ routing: RoutingStatus) -> RoutingStatus {
        var copy = routing
        copy.routes = routing.routes.map { route in
            var masked = route
            masked.gateway = route.gateway.map(mask)
            return masked
        }
        // Resolvers are the exception worth keeping legible: "which DNS am I
        // using" is usually the question, and a public resolver like 1.1.1.1 is
        // not your address — it is a well-known service. Masking it would remove
        // the answer and protect nothing.
        copy.interfaces = routing.interfaces.map { interface in
            var copy = interface
            copy.ipv4 = interface.ipv4.map(mask)
            copy.ipv6 = interface.ipv6.map(mask)
            // A MAC is a stable hardware identifier and never diagnostic here.
            copy.macAddress = interface.macAddress == nil ? nil : "‹mac›"
            copy.subnet = interface.subnet.map {
                Subnet(network: mask($0.network), prefixLength: $0.prefixLength)
            }
            copy.segment = interface.segment.map(sanitise)
            return copy
        }
        return copy
    }

    private static func sanitise(_ segment: NetworkSegment) -> NetworkSegment {
        var copy = segment
        copy.gateway = segment.gateway.map(mask)
        copy.cidr = segment.cidr.map { cidr in
            let parts = cidr.split(separator: "/", maxSplits: 1)
            guard parts.count == 2 else { return mask(cidr) }
            return "\(mask(String(parts[0])))/\(parts[1])"
        }
        return copy
    }
}
