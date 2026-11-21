import Foundation

public struct ProcessTable {
    public struct Proc {
        public var pid: Int32
        public var ppid: Int32
        public var pgid: Int32
        public var uid: uid_t
        public var cpuPct: Double
        public var rssKB: Double
        public var state: String
        public var startSignature: String
        public var commandLine: String

        public var executableName: String {
            guard let first = commandLine.split(separator: " ").first else { return commandLine }
            return (String(first) as NSString).lastPathComponent
        }
    }

    public struct Listener {
        public var pid: Int32
        public var command: String
        public var uid: uid_t
        public var user: String
        public var port: Int
        public var address: String
    }

    public var byPID: [Int32: Proc] = [:]
    public var listeners: [Listener] = []
    public var capturedAt = Date()

    public var processProbeFailed = false
    public var listenerProbeFailed = false

    public var probeFailed: Bool { processProbeFailed || listenerProbeFailed }

    public var pidsByPGID: [Int32: [Int32]] {
        Dictionary(grouping: byPID.values, by: { $0.pgid }).mapValues { $0.map(\.pid) }
    }

    public static func capture(uid: uid_t = geteuid(), includeListeners: Bool = true) -> ProcessTable {
        var table = ProcessTable()
        if let processes = Self.readProcesses() {
            table.byPID = processes
        } else {
            table.processProbeFailed = true
        }
        if includeListeners {
            if let listeners = Self.readListeners() {
                table.listeners = listeners
            } else {
                table.listenerProbeFailed = true
            }
        }
        return table
    }

    static func readProcesses() -> [Int32: Proc]? {
        let result = Shell.run("/bin/ps", ["-Ao", "pid=,ppid=,pgid=,uid=,pcpu=,rss=,state=,lstart=,command="])
        guard result.succeeded else { return nil }
        var table: [Int32: Proc] = [:]
        for line in result.stdout.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 13,
                  let pid = Int32(fields[0]), let ppid = Int32(fields[1]),
                  let pgid = Int32(fields[2]), let uidValue = UInt32(fields[3]),
                  let cpu = Double(fields[4]), let rss = Double(fields[5]) else { continue }
            let state = String(fields[6])
            let startSignature = fields[7...11].joined(separator: " ")
            let command = fields[12...].joined(separator: " ")
            table[pid] = Proc(pid: pid, ppid: ppid, pgid: pgid, uid: uid_t(uidValue),
                              cpuPct: cpu, rssKB: rss, state: state,
                              startSignature: startSignature, commandLine: command)
        }
        return table.isEmpty ? nil : table
    }

    static func readListeners() -> [Listener]? {
        guard let lsof = Shell.which("lsof", candidates: ["/usr/sbin/lsof", "/usr/bin/lsof"]) else {
            return nil
        }
        let result = Shell.run(lsof, ["-nP", "-w", "-iTCP", "-sTCP:LISTEN", "-F", "pcuLn"], timeout: 15)
        if result.stdout.isEmpty {
            guard result.status == 0 || (result.status == 1 && result.stderr.isEmpty) else { return nil }
            return []
        }

        var listeners: [Listener] = []
        var pid: Int32 = 0
        var command = ""
        var uid: uid_t = 0
        var user = ""
        var seen = Set<String>()

        for raw in result.stdout.split(separator: "\n") {
            guard let tag = raw.first else { continue }
            let value = String(raw.dropFirst())
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "u": uid = uid_t(UInt32(value) ?? 0)
            case "L": user = value
            case "n":
                guard let port = Self.port(fromLsofName: value) else { continue }
                let key = "\(pid):\(port)"
                if seen.insert(key).inserted {
                    let address = String(value.prefix(upTo: value.lastIndex(of: ":") ?? value.endIndex))
                    listeners.append(Listener(pid: pid, command: command, uid: uid,
                                              user: user, port: port, address: address))
                }
            default: break
            }
        }
        return listeners
    }

    static func port(fromLsofName name: String) -> Int? {
        guard !name.contains("->") else { return nil }
        guard let colon = name.lastIndex(of: ":") else { return nil }
        let portPart = name[name.index(after: colon)...]
        return Int(portPart)
    }

    public func process(_ pid: Int32) -> Proc? { byPID[pid] }

    public func processes(inGroup pgid: Int32) -> [Proc] {
        byPID.values.filter { $0.pgid == pgid }
    }

    public func listeningPorts(inGroup pgid: Int32) -> [Int] {
        let pids = Set(processes(inGroup: pgid).map(\.pid))
        return Array(Set(listeners.filter { pids.contains($0.pid) }.map(\.port))).sorted()
    }

    public func resourceUsage(inGroup pgid: Int32) -> ResourceSample {
        let procs = processes(inGroup: pgid)
        guard !procs.isEmpty else {
            return ResourceSample(cpuPct: nil, memMB: nil, processCount: 0, sampledAt: capturedAt)
        }
        return ResourceSample(cpuPct: procs.reduce(0) { $0 + $1.cpuPct },
                              memMB: procs.reduce(0) { $0 + $1.rssKB } / 1024.0,
                              processCount: procs.count,
                              sampledAt: capturedAt)
    }
}
