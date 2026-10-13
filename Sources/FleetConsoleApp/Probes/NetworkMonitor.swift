import Foundation
import AppKit
import CoreWLAN
import CoreLocation
import FleetCore

/// Network probes run in the app, not the daemon: Wi-Fi SSID needs Location
/// authorisation, which is granted to a GUI app bundle, not to a launchd agent.
/// Everything here is read-only — FleetConsole never reconfigures your network.

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
    /// True when we are associated but macOS withholds the SSID pending Location access.
    var ssidRequiresLocation = false
    var rssi: Int?
    var noise: Int?
    var transmitRateMbps: Double?
    var channel: String?
    var ipv4: String?
    var checkedAt = Date()

    /// 0…4 bars from RSSI, or nil when not associated.
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
    /// Default route, resolvers and the interface inventory. See `RoutingProbe`.
    var routing = RoutingStatus()
    var isRefreshing = false

    private let probeQueue = DispatchQueue(label: "com.fleetconsole.app.network")
    private var hardwarePorts: [String: String] = [:]   // display name → BSD device
    private var locationManager: CLLocationManager?
    // Nonisolated so `deinit` can invalidate it; nothing observes this handle.
    @ObservationIgnored nonisolated(unsafe) private var refreshTimer: Timer?

    private nonisolated static var allowsLiveProbes: Bool {
        #if FLEET_SURFACE_RENDERER
        !CommandLine.arguments.contains(SurfaceRenderer.flag)
        #else
        true
        #endif
    }

    /// The cadence comes from config, clamped there. A hand-edited `0` would
    /// otherwise mean "fork `netstat`, `ifconfig` and `scutil` continuously".
    init(interval: TimeInterval = FleetConfig.UIConfig.Intervals().clampedNetworkRefresh) {
        guard Self.allowsLiveProbes else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// The run loop holds the timer even though the closure is weak, so it has to
    /// be invalidated here or a per-view instance would strand a live probe cycle.
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
                // Segments are grafted on here rather than inside the probe: the
                // probe reports what this machine can see, and the registry
                // reports what something else told us. Keeping the join at the
                // boundary is what lets the VLAN source be absent without the
                // probe knowing anything about it.
                //
                // The overlay is named here for the same reason and by the same
                // kind of join: `RoutingProbe` sees a `utun` with a CGNAT
                // address and cannot know whose it is, while `probeTailscale`
                // already reported that exact address as this node's. Matching
                // them turns an opaque `utun4` into `Tailscale`, using two facts
                // the app already had and inventing neither.
                let interfaces = Self.nameOverlay(
                    VLANRegistry.shared.annotate(routing.interfaces),
                    tailscaleIPv4: tailscale.ipv4)
                let annotated = RoutingStatus(
                    routes: routing.routes,
                    resolvers: routing.resolvers,
                    searchDomains: routing.searchDomains,
                    interfaces: interfaces,
                    checkedAt: routing.checkedAt)
                // `checkedAt` moves on every pass, so comparing whole snapshots
                // would report a change every time and rebuild the menu for
                // nothing. The equality that matters is the content.
                if !self.routing.sameContent(as: annotated) { self.routing = annotated }
                if self.ethernet != ethernet { self.ethernet = ethernet }
                if self.tailscale != tailscale { self.tailscale = tailscale }
                if self.internet != internet { self.internet = internet }
                if self.vpn != vpn { self.vpn = vpn }
                if self.vlan != vlan { self.vlan = vlan }
                if self.thunderbolt != thunderbolt { self.thunderbolt = thunderbolt }
                if self.exo != exo { self.exo = exo }
                // The Wi-Fi probe used to run here on the main actor, and one
                // CoreWiFi XPC reply (`ssid()` under a pending Location
                // authorization) never arrived — freezing the main thread and
                // with it the whole app, quit included. It is a synchronous
                // system call, so it runs on the probe queue like its siblings,
                // where a late reply can only stall the next refresh.
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

    // MARK: - Interfaces

    // These probes use only local values and synchronous system tools. They are
    // intentionally safe on `probeQueue`; keeping them off the main actor avoids
    // making every network refresh borrow the UI actor.
    /// Gives the Tailscale tunnel its name.
    ///
    /// A `utun` is anonymous by construction — macOS hands them out to anything
    /// that asks, and this machine has eight. Matching one against the address
    /// `tailscale status` reported for this node identifies it exactly, with no
    /// guessing from the CGNAT range: another WireGuard client on 100.64/10
    /// would not match, because the comparison is to *our* address.
    ///
    /// It stays `.tunnel` rather than becoming its own kind. What changes is the
    /// label; a tunnel is still a tunnel, and `hasCarrier` still says link is not
    /// a question you ask of it.
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
        // The built-in wired port is the one named exactly "Ethernet"; adapters are
        // "Ethernet Adapter (enN)" and are only used when the built-in is absent.
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
                // `== "active"`, not `contains("active")` — the other value
                // `ifconfig` prints is *inactive*, which contains it. The bug
                // was invisible here only because the `ipv4 == nil` guard below
                // overrode the wrong answer; it was not invisible in
                // `RoutingProbe`, where it reported link on 22 of 26 interfaces.
                let value = line.dropFirst("status:".count).trimmingCharacters(in: .whitespaces)
                status.connected = value == "active"
            } else if line.hasPrefix("media:") {
                // media: autoselect (1000baseT <full-duplex>)
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
        // Associated is inferred from the radio, not from the SSID: macOS hides the
        // SSID without Location access, and "no SSID" must not read as "offline".
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

    // MARK: - System Settings deep links

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

    /// Asking for Location is the only way macOS will reveal the SSID to us.
    func requestLocationForSSID() {
        let manager = CLLocationManager()
        locationManager = manager
        manager.requestWhenInUseAuthorization()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refresh()
            // The manager exists only to trigger the prompt; holding it past the
            // lookup keeps a location client alive for the life of the app.
            self?.locationManager = nil
        }
    }
}
