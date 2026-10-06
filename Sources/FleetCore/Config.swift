import Foundation

/// User-editable configuration. Written with defaults on first daemon start.
/// The allow-list of "boring" listeners lives here, so adding one is an explicit,
/// reviewable act (threat model T4).
public struct FleetConfig: Codable, Sendable {
    public var supervisorTickSec: Double
    public var reconcileIntervalSec: Double
    public var deviceProbeIntervalSec: Double
    /// Leases longer than this are clamped. Prevents "effectively forever".
    public var maxLeaseSec: Double
    public var defaultLeaseSec: Double
    /// Grace period between SIGTERM and SIGKILL.
    public var stopGraceSec: Double
    /// Evidence older than tick * this factor renders as "unknown (stale)".
    public var staleTickFactor: Double
    /// How long a newly discovered unmanaged process stays in "Needs attention".
    /// After this it is still listed as Unmanaged, but it stops being an alert:
    /// a listener that has been up for hours is furniture, not an incident.
    public var unmanagedGraceSec: Double
    /// How long a crashed service stays in "Needs attention".
    public var crashAttentionSec: Double

    /// Commands whose listeners are expected and are not flagged as unmanaged.
    public var ignoredListenerCommands: [String]
    /// Ports that are never flagged (e.g. system services you accept).
    public var ignoredPorts: [Int]
    /// Listeners at or above this port are treated as ephemeral and not flagged.
    /// The dynamic range is where short-lived helpers land; each one that appears
    /// and vanishes would otherwise write a `becameUnmanaged` event and briefly
    /// raise an alert for something nobody can act on. Set to 0 to flag everything.
    public var ephemeralPortFloor: Int
    /// Argv substrings that make a *non-listening* process look like a dev server.
    public var devServerPatterns: [String]

    /// Your own long-running tools. Anything matching one of these is shown as a
    /// named local tool instead of being flagged as an unmanaged process.
    public var knownServices: [KnownService]

    public struct KnownService: Codable, Sendable, Identifiable {
        public var id: String
        public var name: String
        /// Matched against the full command line, case-insensitively.
        public var match: String
        /// Ports it is expected to listen on; also used for matching.
        public var ports: [Int]
        /// Opened when you click the row.
        public var url: String?
        public var symbol: String?

        public init(id: String, name: String, match: String, ports: [Int] = [],
                    url: String? = nil, symbol: String? = nil) {
            self.id = id
            self.name = name
            self.match = match
            self.ports = ports
            self.url = url
            self.symbol = symbol
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            match = try c.decodeIfPresent(String.self, forKey: .match) ?? ""
            ports = try c.decodeIfPresent([Int].self, forKey: .ports) ?? []
            url = try c.decodeIfPresent(String.self, forKey: .url)
            symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        }
    }

    /// What the app shows, how often it looks, and which guarded verbs are
    /// unlocked. Every field has a default that makes the app correct with no
    /// config file at all — the block exists so a section can be turned *off*,
    /// not so it can be turned on.
    public var ui: UIConfig

    /// Zero setup by default. Each nested struct decodes field-by-field with a
    /// fallback, the same contract as `FleetConfig` itself: a key from a later
    /// version must not make the file undecodable, and a key you delete must
    /// fall back rather than fail the load.
    public struct UIConfig: Codable, Sendable {
        public var sections: Sections
        public var intervals: Intervals
        public var features: Features
        public var consoles: Consoles

        /// Which surfaces render. A section switched off is *absent*, not
        /// greyed: a control you can see and cannot use is the same dead chrome
        /// rule 10 bans from the menus.
        public struct Sections: Codable, Sendable {
            public var services: Bool
            public var agents: Bool
            public var processes: Bool
            public var network: Bool
            public var devices: Bool
            public var listening: Bool

            public init(services: Bool = true, agents: Bool = true, processes: Bool = true,
                        network: Bool = true, devices: Bool = true, listening: Bool = true) {
                self.services = services
                self.agents = agents
                self.processes = processes
                self.network = network
                self.devices = devices
                self.listening = listening
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                let d = Sections()
                services = try c.decodeIfPresent(Bool.self, forKey: .services) ?? d.services
                agents = try c.decodeIfPresent(Bool.self, forKey: .agents) ?? d.agents
                processes = try c.decodeIfPresent(Bool.self, forKey: .processes) ?? d.processes
                network = try c.decodeIfPresent(Bool.self, forKey: .network) ?? d.network
                devices = try c.decodeIfPresent(Bool.self, forKey: .devices) ?? d.devices
                listening = try c.decodeIfPresent(Bool.self, forKey: .listening) ?? d.listening
            }
        }

        /// Cadences, clamped on read. A zero or negative interval in a
        /// hand-edited file would otherwise mean "sample continuously", which
        /// is a `ps -Ao` over every process on the machine in a tight loop.
        /// Two cadences, because the app runs two samplers.
        ///
        /// There was a third — `routingRefreshSec`, default 30 — and it was read
        /// by nothing. It was documented in README.md, clamped here and asserted
        /// by a test, which is three places agreeing about a knob that turned
        /// nothing: routing is captured *inside* `NetworkMonitor.refresh()`, in
        /// the same pass and off the same `readHardwarePorts()` as every other
        /// probe, so it has always run on `networkRefreshSec`.
        ///
        /// Removed rather than wired up, and that is the interesting half. A
        /// separate timer would mean a second overlapping probe pass forking its
        /// own `netstat`, `ifconfig` and `scutil` and re-reading the hardware
        /// ports that `RoutingProbe.capture` already takes as an argument —
        /// paying twice to make the picture *less* coherent, since the gateway
        /// and the Wi-Fi state it is read against would then come from two
        /// different moments. The single pass is the right design; the config key
        /// was describing one that was never built. An existing config.json with
        /// the key still loads — unknown keys are ignored — and now says nothing
        /// instead of saying something false.
        public struct Intervals: Codable, Sendable {
            public var networkRefreshSec: Double
            public var processSampleSec: Double

            public init(networkRefreshSec: Double = 20,
                        processSampleSec: Double = 4) {
                self.networkRefreshSec = networkRefreshSec
                self.processSampleSec = processSampleSec
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                let d = Intervals()
                networkRefreshSec = try c.decodeIfPresent(Double.self, forKey: .networkRefreshSec) ?? d.networkRefreshSec
                processSampleSec = try c.decodeIfPresent(Double.self, forKey: .processSampleSec) ?? d.processSampleSec
            }

            /// The floors are not taste. `ps -Ao` over every process costs far
            /// more than reading a Mach counter, and `netstat -rn` plus
            /// `scutil --dns` fork two more; below these a "refresh" is just a
            /// second copy of the previous one still running.
            public var clampedNetworkRefresh: Double { max(5, networkRefreshSec) }
            public var clampedProcessSample: Double { max(2, processSampleSec) }
        }

        /// Verbs that stay locked until you say otherwise.
        public struct Features: Codable, Sendable {
            /// Unlocks **End Process** on the Processes surface.
            ///
            /// Off by default, and off is the honest default: FleetConsole's
            /// standing rule is that the *controller* never signals a process it
            /// did not start, because a recycled PID must never be hit. This
            /// flag does not weaken that rule — the controller still refuses.
            /// It unlocks a separate, narrower thing: a signal **you** send, to
            /// a process **you** own, from a row you are looking at, after the
            /// app has re-read the process's start signature and confirmed the
            /// PID is still the one the row was drawn from. Three gates, all of
            /// which have to hold; this is the one you control.
            public var allowProcessTermination: Bool

            /// Shows what each agent cost you today in the Agents section.
            ///
            /// Off until the figures have been checked against a provider's own
            /// bill on this machine. The prices are a table written down in
            /// `AgentPricing` rather than fetched, so the first thing a wrong
            /// entry does is put a confident, wrong number on screen — and a
            /// spend figure nobody has verified is worse than no figure, because
            /// it will be believed. Turn it on once, deliberately, after
            /// comparing a day.
            public var showAgentSpend: Bool

            public init(allowProcessTermination: Bool = false, showAgentSpend: Bool = false) {
                self.allowProcessTermination = allowProcessTermination
                self.showAgentSpend = showAgentSpend
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                let d = Features()
                allowProcessTermination = try c.decodeIfPresent(Bool.self, forKey: .allowProcessTermination)
                    ?? d.allowProcessTermination
                showAgentSpend = try c.decodeIfPresent(Bool.self, forKey: .showAgentSpend)
                    ?? d.showAgentSpend
            }
        }

        /// Where the "open the admin console" footers point.
        ///
        /// `network` is `nil` by default and *resolves* to `http://<default
        /// gateway>` at render time, so the footer works on first launch with no
        /// configuration and without this file inventing a URL it cannot know.
        /// A machine with no default route has no gateway, so the footer does
        /// not render — that is the capability rule, applied to a link.
        ///
        /// `vlan` is the documented seam for the VLAN admin console. It is
        /// `nil` here and there is no VLAN source registered, so nothing in the
        /// UI mentions VLAN segments today. See `VLANSource`.
        public struct Consoles: Codable, Sendable {
            public var network: String?
            public var vlan: String?

            public init(network: String? = nil, vlan: String? = nil) {
                self.network = network
                self.vlan = vlan
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                network = try c.decodeIfPresent(String.self, forKey: .network)
                vlan = try c.decodeIfPresent(String.self, forKey: .vlan)
            }
        }

        public init(sections: Sections = Sections(),
                    intervals: Intervals = Intervals(),
                    features: Features = Features(),
                    consoles: Consoles = Consoles()) {
            self.sections = sections
            self.intervals = intervals
            self.features = features
            self.consoles = consoles
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = UIConfig()
            sections = try c.decodeIfPresent(Sections.self, forKey: .sections) ?? d.sections
            intervals = try c.decodeIfPresent(Intervals.self, forKey: .intervals) ?? d.intervals
            features = try c.decodeIfPresent(Features.self, forKey: .features) ?? d.features
            consoles = try c.decodeIfPresent(Consoles.self, forKey: .consoles) ?? d.consoles
        }
    }

    /// The VLAN segments this fleet is divided into, as **you** declare them.
    ///
    /// This exists because of a gap the host cannot close on its own. A Mac on a
    /// trunk port reads its own 802.1Q tag off `ifconfig`; a Mac on an access
    /// port — which is almost every Mac — never sees a tag at all, because the
    /// switch strips it before the frame reaches the NIC. All the host gets is a
    /// subnet and a gateway.
    ///
    /// FleetConsole will not bridge that gap by guessing. `10.10.40.0/24` looks
    /// like VLAN 40 and an app that infers it is right on your network and wrong
    /// on anyone who numbered theirs differently. But *you* know, and saying so
    /// here is an assertion with an author, which is a different thing from a
    /// heuristic — the same distinction `ignoredListenerCommands` draws.
    ///
    /// Empty by default. Nothing renders until something is declared.
    public var networkSegments: [SegmentConfig]

    public struct SegmentConfig: Codable, Sendable, Identifiable {
        /// 802.1Q tag. Optional, because a segment can be a subnet you have
        /// separated without giving it a number.
        public var tag: Int?
        public var name: String
        /// The subnet, in CIDR. This is what matches a host interface on an
        /// access port, where there is no tag to match on.
        public var cidr: String?
        public var gateway: String?
        public var purpose: String?

        public var id: String { cidr ?? tag.map(String.init) ?? name }

        public init(tag: Int? = nil, name: String, cidr: String? = nil,
                    gateway: String? = nil, purpose: String? = nil) {
            self.tag = tag
            self.name = name
            self.cidr = cidr
            self.gateway = gateway
            self.purpose = purpose
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tag = try c.decodeIfPresent(Int.self, forKey: .tag)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Segment"
            cidr = try c.decodeIfPresent(String.self, forKey: .cidr)
            gateway = try c.decodeIfPresent(String.self, forKey: .gateway)
            purpose = try c.decodeIfPresent(String.self, forKey: .purpose)
        }
    }

    public var devices: [DeviceConfig]

    public struct DeviceConfig: Codable, Sendable {
        public var id: String
        public var name: String
        public var model: String
        public var localHost: String?
        public var tailscaleHost: String?
        public var probePort: Int?
        /// Set for the machine FleetConsole itself runs on.
        public var isSelf: Bool
        /// Opt-in: fetch that machine's managed services read-only over SSH.
        /// Off by default — it runs a command on another host.
        public var remoteQuery: Bool
        /// `user@host` for SSH; falls back to the probe target.
        public var sshHost: String?
        /// Path to fleetctl on that machine, if it is not on the default PATH.
        public var remoteFleetctl: String?

        /// Services declared to be running *on that machine*, matched over SSH.
        ///
        /// `knownServices` is the same idea for this machine, and it cannot be
        /// used here: it matches the local process table. The two services that
        /// motivated this — a Buzz relay and an opencode server on another Mac —
        /// are reachable by none of the mechanisms that existed. The relay makes
        /// an *outbound* WebSocket connection and never listens, so there is no
        /// port to probe; the opencode server listens on the remote's loopback,
        /// so its port is unreachable from here by construction; and the
        /// `remoteQuery` path needs that machine to have `fleetctl` installed,
        /// which it does not.
        ///
        /// So: declare them, and match them over the SSH trust you already have.
        /// Read-only, like everything else across the mesh — the records these
        /// produce are marked `claimed`, which is what makes them unsignallable
        /// rather than merely undisplayed as controls.
        public var services: [KnownService]

        public init(id: String, name: String, model: String = "", localHost: String? = nil,
                    tailscaleHost: String? = nil, probePort: Int? = 22, isSelf: Bool = false,
                    remoteQuery: Bool = false, sshHost: String? = nil, remoteFleetctl: String? = nil,
                    services: [KnownService] = []) {
            self.services = services
            self.id = id
            self.name = name
            self.model = model
            self.localHost = localHost
            self.tailscaleHost = tailscaleHost
            self.probePort = probePort
            self.isSelf = isSelf
            self.remoteQuery = remoteQuery
            self.sshHost = sshHost
            self.remoteFleetctl = remoteFleetctl
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
            localHost = try c.decodeIfPresent(String.self, forKey: .localHost)
            tailscaleHost = try c.decodeIfPresent(String.self, forKey: .tailscaleHost)
            probePort = try c.decodeIfPresent(Int.self, forKey: .probePort)
            isSelf = try c.decodeIfPresent(Bool.self, forKey: .isSelf) ?? false
            remoteQuery = try c.decodeIfPresent(Bool.self, forKey: .remoteQuery) ?? false
            sshHost = try c.decodeIfPresent(String.self, forKey: .sshHost)
            remoteFleetctl = try c.decodeIfPresent(String.self, forKey: .remoteFleetctl)
            services = try c.decodeIfPresent([KnownService].self, forKey: .services) ?? []
        }
    }

    public init(supervisorTickSec: Double = 5,
                reconcileIntervalSec: Double = 20,
                deviceProbeIntervalSec: Double = 60,
                maxLeaseSec: Double = 12 * 3600,
                defaultLeaseSec: Double = 3600,
                stopGraceSec: Double = 10,
                staleTickFactor: Double = 3,
                unmanagedGraceSec: Double = 900,
                crashAttentionSec: Double = 900,
                ignoredListenerCommands: [String] = FleetConfig.defaultIgnoredCommands,
                ignoredPorts: [Int] = [22, 88, 445, 631, 3283, 5900, 7000],
                ephemeralPortFloor: Int = 49152,
                devServerPatterns: [String] = FleetConfig.defaultDevServerPatterns,
                knownServices: [KnownService] = FleetConfig.defaultKnownServices,
                ui: UIConfig = UIConfig(),
                networkSegments: [SegmentConfig] = [],
                devices: [DeviceConfig] = []) {
        self.supervisorTickSec = supervisorTickSec
        self.reconcileIntervalSec = reconcileIntervalSec
        self.deviceProbeIntervalSec = deviceProbeIntervalSec
        self.maxLeaseSec = maxLeaseSec
        self.defaultLeaseSec = defaultLeaseSec
        self.stopGraceSec = stopGraceSec
        self.staleTickFactor = staleTickFactor
        self.unmanagedGraceSec = unmanagedGraceSec
        self.crashAttentionSec = crashAttentionSec
        self.ignoredListenerCommands = ignoredListenerCommands
        self.ignoredPorts = ignoredPorts
        self.ephemeralPortFloor = ephemeralPortFloor
        self.devServerPatterns = devServerPatterns
        self.knownServices = knownServices
        self.ui = ui
        self.networkSegments = networkSegments
        self.devices = devices
    }

    /// Hand-written and hand-edited: a key added in a later version must not make
    /// the whole file undecodable, and a key you delete must fall back to the
    /// default rather than failing the load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FleetConfig()
        supervisorTickSec = try c.decodeIfPresent(Double.self, forKey: .supervisorTickSec) ?? d.supervisorTickSec
        reconcileIntervalSec = try c.decodeIfPresent(Double.self, forKey: .reconcileIntervalSec) ?? d.reconcileIntervalSec
        deviceProbeIntervalSec = try c.decodeIfPresent(Double.self, forKey: .deviceProbeIntervalSec) ?? d.deviceProbeIntervalSec
        maxLeaseSec = try c.decodeIfPresent(Double.self, forKey: .maxLeaseSec) ?? d.maxLeaseSec
        defaultLeaseSec = try c.decodeIfPresent(Double.self, forKey: .defaultLeaseSec) ?? d.defaultLeaseSec
        stopGraceSec = try c.decodeIfPresent(Double.self, forKey: .stopGraceSec) ?? d.stopGraceSec
        staleTickFactor = try c.decodeIfPresent(Double.self, forKey: .staleTickFactor) ?? d.staleTickFactor
        unmanagedGraceSec = try c.decodeIfPresent(Double.self, forKey: .unmanagedGraceSec) ?? d.unmanagedGraceSec
        crashAttentionSec = try c.decodeIfPresent(Double.self, forKey: .crashAttentionSec) ?? d.crashAttentionSec
        ignoredListenerCommands = try c.decodeIfPresent([String].self, forKey: .ignoredListenerCommands) ?? d.ignoredListenerCommands
        ignoredPorts = try c.decodeIfPresent([Int].self, forKey: .ignoredPorts) ?? d.ignoredPorts
        ephemeralPortFloor = try c.decodeIfPresent(Int.self, forKey: .ephemeralPortFloor) ?? d.ephemeralPortFloor
        devServerPatterns = try c.decodeIfPresent([String].self, forKey: .devServerPatterns) ?? d.devServerPatterns
        knownServices = try c.decodeIfPresent([KnownService].self, forKey: .knownServices) ?? d.knownServices
        ui = try c.decodeIfPresent(UIConfig.self, forKey: .ui) ?? d.ui
        networkSegments = try c.decodeIfPresent([SegmentConfig].self, forKey: .networkSegments) ?? d.networkSegments
        devices = try c.decodeIfPresent([DeviceConfig].self, forKey: .devices) ?? d.devices
    }

    public static let defaultIgnoredCommands: [String] = [
        "rapportd", "ARDAgent", "sharingd", "AirPlayXPCHelper", "identityservicesd",
        "Spotify", "Raycast", "Docker", "com.docker.backend", "OrbStack", "Dropbox",
        "Code Helper", "Code", "Cursor", "Electron", "Xcode", "Simulator", "CoreSimulator",
        "iTerm2", "Terminal", "Slack", "zoom.us", "Music", "Photos", "steam_osx",
        "SSHelper", "launchd", "loginwindow", "ControlCenter", "Tailscale", "tailscaled",
        "syncthing", "node_exporter", "sshd", "smbd", "cupsd", "mDNSResponder",
    ]

    /// Seeded from what was actually found running on this machine, so the
    /// inventory is useful on first launch instead of empty.
    public static let defaultKnownServices: [KnownService] = [
        KnownService(id: "hermes-dashboard", name: "Hermes dashboard",
                     match: "hermes_cli.main dashboard", ports: [9119],
                     url: "http://127.0.0.1:9119", symbol: "gauge.with.dots.needle.33percent"),
        KnownService(id: "eyes1te", name: "eyes1te server",
                     match: "eyes1te-server.py", ports: [8086],
                     url: "http://127.0.0.1:8086", symbol: "eye"),
        KnownService(id: "ssos", name: "SSOS serve",
                     match: "ssos-serve", ports: [8787],
                     url: "http://127.0.0.1:8787", symbol: "tray.full"),
        KnownService(id: "routeflow", name: "Routeflow API",
                     match: "porta_potty.app:app", ports: [8017],
                     url: "http://127.0.0.1:8017", symbol: "arrow.triangle.branch"),
        KnownService(id: "mlx-audio", name: "MLX audio",
                     match: "mlx_audio", ports: [18100], symbol: "waveform"),
        KnownService(id: "cua-driver", name: "CUA driver",
                     match: "cua-driver", symbol: "cursorarrow.rays"),
    ]

    public static let defaultDevServerPatterns: [String] = [
        "vite", "next dev", "next-server", "webpack", "ng serve", "react-scripts",
        "uvicorn", "gunicorn", "flask run", "http.server", "rails server", "puma",
        "nodemon", "ts-node", "bun run", "deno run", "npm run dev", "yarn dev",
        "pnpm dev", "streamlit", "jupyter", "fastapi", "ollama serve",
    ]

    /// Seeded from the local machine + Tailscale peers so the first run is not empty.
    public static func makeDefault(selfHostName: String?, selfTailscaleName: String?) -> FleetConfig {
        var cfg = FleetConfig()
        cfg.devices = [
            DeviceConfig(id: "mac-mini-m4",
                         name: "Mac mini M4",
                         model: "Apple M4",
                         localHost: "localhost",
                         tailscaleHost: selfTailscaleName ?? selfHostName,
                         probePort: 22,
                         isSelf: true),
            DeviceConfig(id: "intel-mac",
                         name: "Intel Mac",
                         model: "Intel",
                         localHost: nil,
                         tailscaleHost: "heavyweights-control",
                         probePort: 22,
                         isSelf: false),
        ]
        return cfg
    }

    public static func load() throws -> FleetConfig {
        let url = FleetPaths.config
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FleetError.notFound("config.json")
        }
        let data = try Data(contentsOf: url)
        return try Codec.decode(FleetConfig.self, from: data)
    }

    public func save() throws {
        try FleetPaths.ensureDirectories()
        let data = try Codec.prettyEncoder.encode(self)
        try data.write(to: FleetPaths.config, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: FleetPaths.config.path)
    }

    /// Loads config, creating it from defaults if missing. Never throws: a broken
    /// config must not stop the controller from reaping leaked processes.
    public static func loadOrCreate(selfHostName: String?, selfTailscaleName: String?) -> (FleetConfig, String?) {
        do {
            return (try load(), nil)
        } catch {
            let fallback = makeDefault(selfHostName: selfHostName, selfTailscaleName: selfTailscaleName)
            if FileManager.default.fileExists(atPath: FleetPaths.config.path) {
                return (fallback, "config.json unreadable (\(error.localizedDescription)); using defaults")
            }
            try? fallback.save()
            return (fallback, nil)
        }
    }
}
