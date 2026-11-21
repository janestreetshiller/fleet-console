import Foundation
import AppKit
import CoreWLAN
import CoreLocation
import FleetCore

struct EthernetStatus: Equatable {
    var interface: String?
    var displayName: String = "Ethernet"
    var connected = false
    var ipv4: String?
    var linkSpeed: String?
    var duplex: String?
    var checkedAt = Date()
}

struct WiFiStatus: Equatable {
    var interface: String?
    var poweredOn = false
    var connected = false
    var ssid: String?
    var ssidRequiresLocation = false
    var rssi: Int?
    var noise: Int?
    var transmitRateMbps: Double?
    var channel: String?
    var ipv4: String?
    var checkedAt = Date()

    var bars: Int? {
        guard connected, let rssi else { return nil }
        switch rssi {
        case (-60)...: return 4
        case (-70)..<(-60): return 3
        case (-80)..<(-70): return 2
        default: return 1
        }
    }

    var signalDescription: String {
        guard let rssi else { return "—" }
        let quality: String
        switch rssi {
        case (-60)...: quality = "excellent"
        case (-70)..<(-60): quality = "good"
        case (-80)..<(-70): quality = "fair"
        default: quality = "weak"
        }
        return "\(rssi) dBm (\(quality))"
    }
}

struct TailscaleUIStatus: Equatable {
    var installed = false
    var running = false
    var backendState = "Unknown"
    var deviceName: String?
    var dnsName: String?
    var ipv4: String?
    var tailnet: String?
    var offersExitNode = false
    var exitNodeName: String?
    var peerCount = 0
    var onlinePeerCount = 0
    var error: String?
    var checkedAt = Date()
}

@Observable
@MainActor
final class NetworkMonitor {
    var ethernet = EthernetStatus()
    var wifi = WiFiStatus()
    var tailscale = TailscaleUIStatus()
    var internet = InternetStatus()
    var vpn = VPNStatus()
    var vlan = VLANStatus()
    var thunderbolt = ThunderboltStatus()
    var exo = ExoStatus()
    var routing = RoutingStatus()
    var isRefreshing = false

    private let probeQueue = DispatchQueue(label: "com.fleetconsole.app.network")
    private var hardwarePorts: [String: String] = [:]
    private var locationManager: CLLocationManager?
    @ObservationIgnored nonisolated(unsafe) private var refreshTimer: Timer?

    private nonisolated static var allowsLiveProbes: Bool {
        #if FLEET_SURFACE_RENDERER
        !CommandLine.arguments.contains(SurfaceRenderer.flag)
        #else
        true
        #endif
    }

    init(interval: TimeInterval = FleetConfig.UIConfig.Intervals().clampedNetworkRefresh) {
        guard Self.allowsLiveProbes else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func refresh() {
        guard Self.allowsLiveProbes else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        probeQueue.async { [weak self] in
            let ports = Self.readHardwarePorts()
            let ethernet = Self.probeEthernet(ports: ports)
            let tailscale = Self.probeTailscale()
            let internet = ConnectionProbes.internet()
            let vpn = ConnectionProbes.vpn(tailscaleIPv4: tailscale.ipv4)
            let vlan = ConnectionProbes.vlan()
            let thunderbolt = ConnectionProbes.thunderbolt(hardwarePorts: ports)
            let exo = ConnectionProbes.exo()
            let routing = RoutingProbe.capture(hardwarePorts: ports)
            Task { @MainActor in
                guard let self else { return }
                self.hardwarePorts = ports
                let interfaces = Self.nameOverlay(
                    VLANRegistry.shared.annotate(routing.interfaces),
                    tailscaleIPv4: tailscale.ipv4)
                let annotated = RoutingStatus(
                    routes: routing.routes,
                    resolvers: routing.resolvers,
                    searchDomains: routing.searchDomains,
                    interfaces: interfaces,
                    checkedAt: routing.checkedAt)
                if !self.routing.sameContent(as: annotated) { self.routing = annotated }
                if self.ethernet != ethernet { self.ethernet = ethernet }
                if self.tailscale != tailscale { self.tailscale = tailscale }
                if self.internet != internet { self.internet = internet }
                if self.vpn != vpn { self.vpn = vpn }
                if self.vlan != vlan { self.vlan = vlan }
                if self.thunderbolt != thunderbolt { self.thunderbolt = thunderbolt }
                if self.exo != exo { self.exo = exo }
                let portsForWiFi = ports
                self.probeQueue.async { [weak self] in
                    let wifi = Self.probeWiFi(ports: portsForWiFi)
                    Task { @MainActor in
                        guard let self else { return }
                        if self.wifi != wifi { self.wifi = wifi }
                        self.isRefreshing = false
                    }
                }
            }
        }
    }

    func refreshEthernetOnly() {
        guard Self.allowsLiveProbes else { return }
        probeQueue.async { [weak self] in
            let ports = Self.readHardwarePorts()
            let status = Self.probeEthernet(ports: ports)
            Task { @MainActor in self?.ethernet = status }
        }
    }

    func refreshTailscaleOnly() {
        guard Self.allowsLiveProbes else { return }
        probeQueue.async { [weak self] in
            let status = Self.probeTailscale()
            Task { @MainActor in self?.tailscale = status }
        }
    }

    nonisolated static func nameOverlay(_ interfaces: [NetworkInterface],
                                        tailscaleIPv4: String?) -> [NetworkInterface] {
        guard let address = tailscaleIPv4, !address.isEmpty else { return interfaces }
        return interfaces.map { interface in
            guard interface.kind == .tunnel, interface.ipv4.contains(address) else { return interface }
            var named = interface
            named.displayName = "Tailscale"
            return named
        }
    }

    nonisolated static func readHardwarePorts() -> [String: String] {
        let result = Shell.run("/usr/sbin/networksetup", ["-listallhardwareports"], timeout: 8)
        var ports: [String: String] = [:]
        var currentPort: String?
        for line in result.stdout.split(separator: "\n") {
            if line.hasPrefix("Hardware Port: ") {
                currentPort = String(line.dropFirst("Hardware Port: ".count))
            } else if line.hasPrefix("Device: "), let port = currentPort {
                ports[port] = String(line.dropFirst("Device: ".count))
                currentPort = nil
            }
        }
        return ports
    }

    nonisolated static func probeEthernet(ports: [String: String]) -> EthernetStatus {
        let name = ports.keys.first { $0 == "Ethernet" }
            ?? ports.keys.filter { $0.hasPrefix("Ethernet") }.sorted().first
        guard let name, let device = ports[name] else {
            return EthernetStatus(interface: nil, displayName: "Ethernet", connected: false)
        }
        var status = EthernetStatus(interface: device, displayName: name)
        let ifconfig = Shell.run("/sbin/ifconfig", [device], timeout: 5)
        for raw in ifconfig.stdout.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("status:") {
                let value = line.dropFirst("status:".count).trimmingCharacters(in: .whitespaces)
                status.connected = value == "active"
            } else if line.hasPrefix("media:") {
                if let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")") {
                    let inner = String(line[line.index(after: open)..<close])
                    let parts = inner.split(separator: " ", maxSplits: 1)
                    status.linkSpeed = parts.first.map(String.init)
                    if inner.contains("full-duplex") { status.duplex = "full duplex" }
                    else if inner.contains("half-duplex") { status.duplex = "half duplex" }
                }
            }
        }
        status.ipv4 = ipv4Address(for: device)
        if status.ipv4 == nil { status.connected = false }
        return status
    }

    nonisolated static func probeWiFi(ports: [String: String]) -> WiFiStatus {
        let device = ports["Wi-Fi"] ?? ports["AirPort"]
        var status = WiFiStatus(interface: device)
        guard let interface = device.flatMap({ CWWiFiClient.shared().interface(withName: $0) })
                ?? CWWiFiClient.shared().interface() else {
            return status
        }
        status.interface = interface.interfaceName ?? device
        status.poweredOn = interface.powerOn()
        let rssi = interface.rssiValue()
        status.rssi = rssi == 0 ? nil : rssi
        status.noise = interface.noiseMeasurement() == 0 ? nil : interface.noiseMeasurement()
        let rate = interface.transmitRate()
        status.transmitRateMbps = rate > 0 ? rate : nil
        if let channel = interface.wlanChannel() {
            let band = channel.channelBand == .band2GHz ? "2.4 GHz" : "5/6 GHz"
            status.channel = "ch \(channel.channelNumber) · \(band)"
        }
        status.ssid = interface.ssid()
        status.ipv4 = status.interface.flatMap { Self.ipv4Address(for: $0) }
        status.connected = status.poweredOn && (status.rssi != nil || status.ipv4 != nil)
        status.ssidRequiresLocation = status.connected && status.ssid == nil
        return status
    }

    nonisolated static func probeTailscale() -> TailscaleUIStatus {
        var status = TailscaleUIStatus()
        switch TailscaleClient.status() {
        case .notInstalled:
            status.installed = false
            status.error = "tailscale CLI not found"
        case .failed(let message):
            status.installed = true
            status.error = message
        case .ok(let value):
            status.installed = true
            status.backendState = value.backendState
            status.running = value.isRunning
            status.tailnet = value.tailnetName
            status.peerCount = value.peers.count
            status.onlinePeerCount = value.peers.filter(\.online).count
            status.exitNodeName = value.activeExitNode?.shortName
            if let node = value.selfNode {
                status.deviceName = node.shortName
                status.dnsName = node.dnsName.hasSuffix(".") ? String(node.dnsName.dropLast()) : node.dnsName
                status.ipv4 = node.ipv4
                status.offersExitNode = node.offersExitNode
            }
        }
        return status
    }

    nonisolated static func ipv4Address(for interface: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard String(cString: current.pointee.ifa_name) == interface,
                  let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return String(nulTerminated: host)
        }
        return nil
    }

    enum SettingsPane: String {
        case network = "x-apple.systempreferences:com.apple.Network-Settings.extension"
        case wifi = "x-apple.systempreferences:com.apple.wifi-settings-extension"
        case location = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices"
        case loginItems = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    }

    func openSettings(_ pane: SettingsPane) {
        guard let url = URL(string: pane.rawValue) else { return }
        NSWorkspace.shared.open(url)
    }

    func requestLocationForSSID() {
        let manager = CLLocationManager()
        locationManager = manager
        manager.requestWhenInUseAuthorization()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refresh()
            self?.locationManager = nil
        }
    }
}
