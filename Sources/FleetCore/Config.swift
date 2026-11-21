import Foundation

public struct FleetConfig: Codable, Sendable {
    public var supervisorTickSec: Double
    public var reconcileIntervalSec: Double
    public var deviceProbeIntervalSec: Double
    public var maxLeaseSec: Double
    public var defaultLeaseSec: Double
    public var stopGraceSec: Double
    public var staleTickFactor: Double
    public var unmanagedGraceSec: Double
    public var crashAttentionSec: Double

    public var ignoredListenerCommands: [String]
    public var ignoredPorts: [Int]
    public var ephemeralPortFloor: Int
    public var devServerPatterns: [String]

    public var knownServices: [KnownService]

    public struct KnownService: Codable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var match: String
        public var ports: [Int]
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

    public var ui: UIConfig

    public struct UIConfig: Codable, Sendable {
        public var sections: Sections
        public var intervals: Intervals
        public var features: Features
        public var consoles: Consoles

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

            public var clampedNetworkRefresh: Double { max(5, networkRefreshSec) }
            public var clampedProcessSample: Double { max(2, processSampleSec) }
        }

        public struct Features: Codable, Sendable {
            public var allowProcessTermination: Bool

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

    public var networkSegments: [SegmentConfig]

    public struct SegmentConfig: Codable, Sendable, Identifiable {
        public var tag: Int?
        public var name: String
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
        public var isSelf: Bool
        public var remoteQuery: Bool
        public var sshHost: String?
        public var remoteFleetctl: String?

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

    public static let defaultKnownServices: [KnownService] = []

    public static let defaultDevServerPatterns: [String] = [
        "vite", "next dev", "next-server", "webpack", "ng serve", "react-scripts",
        "uvicorn", "gunicorn", "flask run", "http.server", "rails server", "puma",
        "nodemon", "ts-node", "bun run", "deno run", "npm run dev", "yarn dev",
        "pnpm dev", "streamlit", "jupyter", "fastapi", "ollama serve",
    ]

    public static func makeDefault(selfHostName: String?, selfTailscaleName: String?) -> FleetConfig {
        var cfg = FleetConfig()
        cfg.devices = [DeviceConfig(id: "self", name: selfHostName ?? "This Mac",
                                   localHost: "localhost", tailscaleHost: selfTailscaleName,
                                   probePort: nil, isSelf: true)]
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
