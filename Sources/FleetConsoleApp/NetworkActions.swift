import Foundation
import AppKit
import FleetCore

@Observable
@MainActor
final class NetworkActions {
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

    @discardableResult
    func copy(_ value: String, label: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        lastOutcome = Outcome(title: "Copied \(label)", output: trimmed, succeeded: true)
        return true
    }

    func pingGateway(_ address: String) {
        run(title: "ping \(address)", tool: "/sbin/ping",
            arguments: ["-c", "4", "-t", "6", address], timeout: 12)
    }

    func traceroute(_ address: String) {
        run(title: "traceroute \(address)", tool: "/usr/sbin/traceroute",
            arguments: ["-n", "-w", "1", "-q", "1", "-m", "12", address], timeout: 25)
    }

    func clearOutcome() { lastOutcome = nil }

    #if FLEET_SURFACE_RENDERER
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
        copy.interfaces = routing.interfaces.map { interface in
            var copy = interface
            copy.ipv4 = interface.ipv4.map(mask)
            copy.ipv6 = interface.ipv6.map(mask)
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
