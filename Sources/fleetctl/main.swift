import Foundation
import FleetCore

// fleetctl — the launcher agents call instead of spawning background processes
// themselves. Every managed process in FleetConsole enters the registry here.

let usage = """
fleetctl — request and control managed background services

USAGE
  ── asking for a process ──────────────────────────────────────────────────────
  fleetctl launch  --name <name> --owner <agent> --purpose <why> [options] -- <command> [args…]
  fleetctl renew   <id|name> [--lease 30m]        extend the lease
  fleetctl stop    <id|name> [--reason "…"]       SIGTERM the process group, then SIGKILL
  fleetctl restart <id|name> [--reason "…"]       re-run the recorded argv
  fleetctl pause   <id|name>                      SIGSTOP — keeps ports and memory
  fleetctl resume  <id|name>                      SIGCONT
  fleetctl kill    <id|name> [--reason "…"]       SIGKILL now, no grace period

  ── talking to the operator ───────────────────────────────────────────────────
  fleetctl notify --agent <a> --message "…" [--ask] [--problem] [--service <id>]
  fleetctl inbox  [--agent <a>] [--unanswered] [--json]
  fleetctl reply  <message-id> "…"

  ── looking at what is running ────────────────────────────────────────────────
  fleetctl list    [--all] [--json]               managed + unmanaged + attention
  fleetctl show    <id|name> [--json]             one service in full
  fleetctl agents  [--json]                       what each agent has left running
  fleetctl events  [<id|name>] [--limit 50] [--json] [--offline]
                                                  --offline reads the registry directly,
                                                  so history stays readable with no daemon
  fleetctl logs    <id|name> [--err] [--bytes 64000]
  fleetctl ping                                   is the controller alive
  fleetctl doctor                                 check the whole install

  ── housekeeping ──────────────────────────────────────────────────────────────
  fleetctl reconcile                              sweep for processes outside the registry
  fleetctl claim   <pid|id> [--name <s>] [--owner <a>] [--purpose <why>] [--lease 1h]
                                                  adopt a running process into the registry:
                                                  it gets an owner, a lease and a timeline,
                                                  and the controller still will not signal it
  fleetctl ignore  <command>                      "this listener is expected" → allow-list
  fleetctl prune   [--older-than 1h]              drop old stopped/crashed records
  fleetctl config  [--path | --reload]            show or reload config.json

  Every read command accepts --json for scripting.

LAUNCH OPTIONS
  --name <s>            friendly name shown in the console            (required)
  --owner <s>           which agent is asking for this                (required)
  --purpose <s>         why this process needs to exist               (required)
  --cwd <path>          project folder                    (default: current directory)
  --port <n>            port this service is expected to bind    (repeatable)
  --lease <dur>         how long before the controller reaps it  (default 1h)
  --max-runtime <dur>   hard ceiling regardless of renewals
  --cpu-warn <pct>      warn above this CPU percentage
  --mem-warn <mb>       warn above this resident size in MB
  --allow-port <n>      port the service may bind          (repeatable; defaults to --port)
  --health-http <url>   HTTP health check (localhost only)
  --health-tcp <h:p>    TCP connect health check
  --health-interval <d> how often to check                  (default 15s)
  --expect-status <n>   expected HTTP status                (default 200)
  --env KEY=VALUE       extra environment      (repeatable; values are never stored)
  --json                print the managed service record as JSON

DURATIONS
  30s, 15m, 2h, 1d, or a plain number of seconds.

NOTES
  Agents must not start persistent processes directly. Ask for one here and the
  controller records the owner, purpose, ports, lease and expiry, then cleans up
  when the lease runs out — whether or not the agent is still around.

  `claim` is not a way around that. A launched service is one the controller
  started, so it owns the consequences of stopping it; a claimed one was already
  running when we found it. Claiming buys visibility — an owner, a purpose, a
  lease, a timeline and a row that is no longer labelled "unmanaged" — and buys
  no authority at all: stop, restart, pause, resume, kill and the lease reaper
  all refuse a claimed record. Stop it where you started it.
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("fleetctl: \(message)\n".utf8))
    exit(code)
}

func parseDuration(_ text: String) -> Double? {
    guard let last = text.last else { return nil }
    if let plain = Double(text) { return plain }
    let value = Double(text.dropLast())
    guard let value else { return nil }
    switch last {
    case "s": return value
    case "m": return value * 60
    case "h": return value * 3600
    case "d": return value * 86400
    default: return nil
    }
}

/// Tiny argument reader. Everything after `--` is the command to run, untouched.
struct Args {
    var flags: [String: [String]] = [:]
    var positional: [String] = []
    var trailing: [String] = []

    init(_ argv: [String]) {
        var iterator = argv.makeIterator()
        var afterSeparator = false
        var pending: String?
        while let token = iterator.next() {
            if afterSeparator { trailing.append(token); continue }
            if token == "--" { afterSeparator = true; continue }
            if token.hasPrefix("--") {
                if let key = pending { flags[key, default: []].append("true") }
                pending = String(token.dropFirst(2))
            } else if let key = pending {
                flags[key, default: []].append(token)
                pending = nil
            } else {
                positional.append(token)
            }
        }
        if let key = pending { flags[key, default: []].append("true") }
    }

    func first(_ key: String) -> String? { flags[key]?.first }
    func all(_ key: String) -> [String] { flags[key] ?? [] }
    func has(_ key: String) -> Bool { flags[key] != nil }
    func int(_ key: String) -> Int? { first(key).flatMap(Int.init) }
    func double(_ key: String) -> Double? { first(key).flatMap(Double.init) }
    func duration(_ key: String) -> Double? { first(key).flatMap(parseDuration) }
}

func send(_ request: RPCRequest, timeout: TimeInterval = 30) -> RPCResponse {
    do {
        return try UnixSocketClient.send(request, timeout: timeout)
    } catch {
        fail("""
             \(error.localizedDescription)
             Is the controller running?  launchctl print gui/$(id -u)/\(FleetPaths.agentLabel)
             """, code: 69)
    }
}

func stateGlyph(_ state: ServiceState) -> String {
    switch state {
    case .healthy: return "OK "
    case .running: return "RUN"
    case .paused: return "||  "
    case .starting: return "…  "
    case .degraded: return "!  "
    case .unhealthy: return "FAIL"
    case .expiring: return "EXP"
    case .expired: return "GONE"
    case .stopping: return "STP"
    case .stopped: return "-  "
    case .crashed: return "XXX"
    }
}

/// String(format:) does not pad %@ arguments, so columns are padded by hand.
func pad(_ text: String, _ width: Int) -> String {
    let clipped = text.count > width ? String(text.prefix(width - 1)) + "…" : text
    return clipped.padding(toLength: width, withPad: " ", startingAt: 0)
}

func printServiceTable(_ snapshot: Snapshot, includeTerminal: Bool) {
    let services = includeTerminal ? snapshot.services : snapshot.activeServices
    if services.isEmpty {
        print("No managed services.")
    } else {
        print(pad("STATE", 6) + pad("ID", 10) + pad("NAME", 22) + pad("OWNER", 12)
              + pad("PORTS", 14) + pad("PID", 8) + pad("UPTIME", 10) + "LEASE")
        for service in services {
            let lease = service.state.isTerminal ? "—" :
                (service.leaseRemaining > 0 ? "in \(Fmt.duration(service.leaseRemaining))" : "expired")
            print(pad(stateGlyph(service.state), 6)
                  + pad(service.shortID, 10)
                  + pad(service.friendlyName, 22)
                  + pad(service.ownerAgent, 12)
                  + pad(Fmt.ports(service.effectivePorts), 14)
                  + pad(service.pid.map(String.init) ?? "—", 8)
                  + pad(Fmt.duration(service.uptime), 10)
                  + lease)
        }
    }

    if !snapshot.unmanaged.isEmpty {
        print("\nUNMANAGED (not launched through the controller)")
        for process in snapshot.unmanaged {
            print("  " + pad(String(process.pid), 8) + pad(process.command, 18)
                  + pad(Fmt.ports(process.ports), 14) + process.reason.label)
        }
    }

    if !snapshot.attention.isEmpty {
        print("\nNEEDS ATTENTION")
        for item in snapshot.attention {
            print("  [\(item.severity == .critical ? "!" : "~")] \(item.title) — \(item.detail)")
        }
    }
}

func describe(_ service: ServiceRecord) {
    print("""
          \(service.friendlyName)  [\(service.state.rawValue)]
            id         \(service.id)
            owner      \(service.ownerAgent)
            purpose    \(service.purpose)
            command    \(service.commandLine)
            cwd        \(service.cwd)
            pid/pgid   \(service.pid.map(String.init) ?? "—") / \(service.pgid.map(String.init) ?? "—")
            ports      declared \(Fmt.ports(service.declaredPorts)) · listening \(service.evidence.portScanRan ? Fmt.ports(service.evidence.listeningPorts) : "not checked yet")
            lease      expires \(Fmt.relative(service.leaseExpiresAt)) (ttl \(Fmt.duration(service.leaseTTLSec)))
            health     \(service.health.kind == .none ? "no check configured — cannot be reported healthy" : (service.evidence.healthDetail ?? "not checked yet"))
            logs       \(service.stdoutPath)
          """)
}

// MARK: - Dispatch

let argv = Array(CommandLine.arguments.dropFirst())
guard let subcommand = argv.first, !subcommand.hasPrefix("-") else {
    print(usage)
    exit(argv.isEmpty ? 1 : 0)
}
let args = Args(Array(argv.dropFirst()))

switch subcommand {
case "help", "-h", "--help":
    print(usage)

case "ping":
    let response = send(RPCRequest(op: .ping), timeout: 5)
    guard response.ok, let daemon = response.daemon else { fail(response.error ?? "no reply") }
    print("controller \(daemon.version) · pid \(daemon.pid) · up \(Fmt.duration(daemon.uptime)) · tick \(Int(daemon.tickIntervalSec))s")
    print("last tick \(Fmt.relative(daemon.lastTickAt)) · last reconcile \(Fmt.relative(daemon.lastReconcileAt))")

case "launch":
    guard !args.trailing.isEmpty else {
        fail("no command given — put it after `--`, e.g. fleetctl launch … -- python3 -m http.server 8000")
    }
    guard let name = args.first("name") else { fail("--name is required") }
    guard let owner = args.first("owner") else { fail("--owner is required") }
    guard let purpose = args.first("purpose") else { fail("--purpose is required") }

    let cwd = args.first("cwd") ?? FileManager.default.currentDirectoryPath
    let ports = args.all("port").compactMap(Int.init)
    var env: [String: String] = [:]
    for pair in args.all("env") {
        guard let idx = pair.firstIndex(of: "=") else { fail("--env expects KEY=VALUE, got '\(pair)'") }
        env[String(pair[pair.startIndex..<idx])] = String(pair[pair.index(after: idx)...])
    }

    var health = HealthSpec()
    if let url = args.first("health-http") {
        health = HealthSpec(kind: .http, target: url,
                            intervalSec: args.duration("health-interval") ?? 15,
                            timeoutSec: args.duration("health-timeout") ?? 4,
                            expectStatus: args.int("expect-status") ?? 200,
                            failureThreshold: args.int("failure-threshold") ?? 3)
    } else if let target = args.first("health-tcp") {
        health = HealthSpec(kind: .tcp, target: target,
                            intervalSec: args.duration("health-interval") ?? 15,
                            timeoutSec: args.duration("health-timeout") ?? 4,
                            failureThreshold: args.int("failure-threshold") ?? 3)
    }

    let budget = ResourceBudget(maxRuntimeSec: args.duration("max-runtime"),
                                cpuWarnPct: args.double("cpu-warn"),
                                memWarnMB: args.double("mem-warn"),
                                allowedPorts: args.all("allow-port").compactMap(Int.init))

    let request = LaunchRequest(friendlyName: name,
                                ownerAgent: owner,
                                purpose: purpose,
                                command: args.trailing,
                                cwd: cwd,
                                env: env,
                                declaredPorts: ports,
                                leaseTTLSec: args.duration("lease") ?? 3600,
                                budget: budget,
                                health: health)

    let response = send(RPCRequest(op: .launch, launch: request))
    guard response.ok, let service = response.service else { fail(response.error ?? "launch failed") }
    if args.has("json") {
        print(Codec.jsonString(service, pretty: true))
    } else {
        print("launched \(service.friendlyName) — id \(service.id)")
        print("  pid \(service.pid.map(String.init) ?? "?") · lease expires \(Fmt.relative(service.leaseExpiresAt))")
        print("  renew with: fleetctl renew \(service.shortID) --lease \(Int(service.leaseTTLSec / 60))m")
    }

case "renew":
    guard let id = args.positional.first else { fail("renew needs a service id or name") }
    let response = send(RPCRequest(op: .renew, serviceID: id, ttlSec: args.duration("lease")))
    guard response.ok, let service = response.service else { fail(response.error ?? "renew failed") }
    if args.has("json") {
        print(Codec.jsonString(service, pretty: true))
    } else {
        print("\(service.friendlyName): lease now expires \(Fmt.relative(service.leaseExpiresAt))")
    }

case "stop":
    guard let id = args.positional.first else { fail("stop needs a service id or name") }
    let response = send(RPCRequest(op: .stop, serviceID: id, reason: args.first("reason") ?? "fleetctl stop"))
    guard response.ok, let service = response.service else { fail(response.error ?? "stop failed") }
    print("\(service.friendlyName): SIGTERM sent to process group \(service.pgid.map(String.init) ?? "?")")

case "restart":
    guard let id = args.positional.first else { fail("restart needs a service id or name") }
    let response = send(RPCRequest(op: .restart, serviceID: id,
                                   reason: args.first("reason") ?? "fleetctl restart"), timeout: 60)
    guard response.ok, let service = response.service else { fail(response.error ?? "restart failed") }
    print("\(service.friendlyName): restarted as \(service.shortID), pid \(service.pid.map(String.init) ?? "?")")

case "list", "ls", "status":
    let response = send(RPCRequest(op: .snapshot))
    guard response.ok, let snapshot = response.snapshot else { fail(response.error ?? "no snapshot") }
    if args.has("json") {
        print(Codec.jsonString(snapshot, pretty: true))
    } else {
        printServiceTable(snapshot, includeTerminal: args.has("all"))
    }

case "show", "info":
    guard let id = args.positional.first else { fail("show needs a service id or name") }
    let response = send(RPCRequest(op: .snapshot))
    guard let snapshot = response.snapshot else { fail(response.error ?? "no snapshot") }
    let needle = id.lowercased()
    guard let service = snapshot.services.first(where: {
        $0.id.lowercased().hasPrefix(needle) || $0.friendlyName.lowercased() == needle
    }) else { fail("no service matching '\(id)'") }
    if args.has("json") { print(Codec.jsonString(service, pretty: true)) } else { describe(service) }

case "events":
    let limit = args.int("limit") ?? 50
    let events: [ServiceEvent]
    if args.has("offline") {
        // Every other read verb goes over the socket and exits 69 when nothing answers —
        // i.e. history becomes unreadable at exactly the moment you need it, which is
        // after the controller died. This path opens the registry read-only instead.
        do {
            let registry = try Registry(readOnly: true)
            let serviceID = try args.positional.first.flatMap { needle -> String? in
                guard let record = try registry.resolve(idOrPrefix: needle) else {
                    fail("no service matching '\(needle)' in \(FleetPaths.database.path)")
                }
                return record.id
            }
            events = try registry.events(serviceID: serviceID, limit: limit)
        } catch {
            fail("cannot read \(FleetPaths.database.path): \(error.localizedDescription)")
        }
    } else {
        let response = send(RPCRequest(op: .events, serviceID: args.positional.first, limit: limit))
        guard response.ok, let fetched = response.events else { fail(response.error ?? "no events") }
        events = fetched
    }
    if args.has("json") {
        print(Codec.jsonString(events, pretty: true))
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        for event in events.reversed() {
            let name = event.serviceName.map { "[\($0)] " } ?? ""
            print("\(formatter.string(from: event.ts))  \(event.kind.rawValue.padding(toLength: 18, withPad: " ", startingAt: 0)) \(name)\(event.detail)")
        }
    }

case "logs":
    guard let id = args.positional.first else { fail("logs needs a service id or name") }
    let response = send(RPCRequest(op: .logs, serviceID: id,
                                   stream: args.has("err") ? "err" : "out",
                                   maxBytes: args.int("bytes") ?? 64_000))
    guard response.ok, let chunk = response.logs else { fail(response.error ?? "no logs") }
    if chunk.truncated { print("… showing the last \(chunk.text.utf8.count) of \(chunk.bytes) bytes from \(chunk.path)\n") }
    print(chunk.text)

case "pause", "resume", "kill":
    guard let id = args.positional.first else { fail("\(subcommand) needs a service id or name") }
    let op: RPCOp = subcommand == "pause" ? .pause : (subcommand == "resume" ? .resume : .kill)
    let response = send(RPCRequest(op: op, serviceID: id, reason: args.first("reason") ?? "fleetctl \(subcommand)"))
    guard response.ok, let service = response.service else { fail(response.error ?? "\(subcommand) failed") }
    switch subcommand {
    case "pause":
        print("\(service.friendlyName): paused (SIGSTOP). It still holds \(Fmt.ports(service.effectivePorts)) and its memory.")
    case "resume":
        print("\(service.friendlyName): resumed (SIGCONT).")
    default:
        print("\(service.friendlyName): SIGKILL sent to process group \(service.pgid.map(String.init) ?? "?").")
    }

case "notify":
    guard let agent = args.first("agent") else { fail("--agent is required") }
    guard let body = args.first("message") ?? args.positional.first else { fail("--message is required") }
    let kind: MessageKind = args.has("problem") ? .problem : (args.has("ask") ? .question : .status)
    let response = send(RPCRequest(op: .postMessage, serviceID: args.first("service"),
                                   agent: agent, body: body, kind: kind,
                                   needsReply: args.has("ask") || args.has("needs-reply")))
    guard response.ok, let message = response.message else { fail(response.error ?? "could not post") }
    if args.has("json") {
        print(Codec.jsonString(message, pretty: true))
    } else {
        print("posted message \(message.id) from \(message.agent)"
              + (message.needsReply ? " — awaiting a reply; poll with `fleetctl inbox --agent \(agent)`" : ""))
    }

case "inbox":
    let response = send(RPCRequest(op: .messages, limit: args.int("limit") ?? 50,
                                   agent: args.first("agent"),
                                   unansweredOnly: args.has("unanswered")))
    guard response.ok, let messages = response.messages else { fail(response.error ?? "no messages") }
    if args.has("json") {
        print(Codec.jsonString(messages, pretty: true))
    } else if messages.isEmpty {
        print("No messages.")
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        for message in messages.reversed() {
            let flag = message.isAwaitingReply ? "?" : (message.reply != nil ? "✓" : " ")
            print("\(flag) [\(message.id)] \(formatter.string(from: message.createdAt)) \(pad(message.agent, 10)) \(pad(message.kind.label, 9)) \(message.body)")
            if let reply = message.reply {
                print("      ↳ \(reply)")
            }
        }
    }

case "reply":
    guard let idText = args.positional.first, let messageID = Int64(idText) else {
        fail("reply needs a message id, e.g. `fleetctl reply 7 \"yes, go ahead\"`")
    }
    guard let body = args.positional.dropFirst().first ?? args.first("message") else {
        fail("reply needs text")
    }
    let response = send(RPCRequest(op: .reply, body: body, messageID: messageID))
    guard response.ok, let message = response.message else { fail(response.error ?? "reply failed") }
    print("answered message \(message.id) to \(message.agent).")

case "agents":
    let response = send(RPCRequest(op: .snapshot))
    guard let snapshot = response.snapshot else { fail(response.error ?? "no snapshot") }
    let agents = snapshot.agentSummaries
    if args.has("json") {
        print(Codec.jsonString(agents, pretty: true))
    } else if agents.isEmpty {
        print("No agent has anything running.")
    } else {
        print(pad("AGENT", 14) + pad("RUNNING", 9) + pad("ATTN", 6) + pad("ASK", 5) + pad("PORTS", 16)
              + pad("CPU", 8) + pad("MEM", 10) + "NEXT LEASE")
        for agent in agents {
            print(pad(agent.id, 14)
                  + pad("\(agent.running)", 9)
                  + pad(agent.needingAttention > 0 ? "\(agent.needingAttention)" : "—", 6)
                  + pad(agent.awaitingReply > 0 ? "\(agent.awaitingReply)" : "—", 5)
                  + pad(Fmt.ports(agent.ports), 16)
                  + pad(Fmt.cpu(agent.totalCPU), 8)
                  + pad(Fmt.mem(agent.totalMemMB), 10)
                  + (agent.nextLeaseExpiry.map { Fmt.relative($0) } ?? "—"))
        }
        for agent in agents where !agent.purposes.isEmpty {
            print("\n  \(agent.id): \(agent.purposes.joined(separator: "; "))")
        }
    }

case "doctor":
    var problems = 0
    func check(_ label: String, _ ok: Bool, _ detail: String) {
        print("  \(ok ? "✓" : "✗") \(pad(label, 26))\(detail)")
        if !ok { problems += 1 }
    }
    print("FleetConsole install check\n")

    let socketExists = FileManager.default.fileExists(atPath: FleetPaths.socket.path)
    check("control socket", socketExists, FleetPaths.socket.path)
    if socketExists,
       let attrs = try? FileManager.default.attributesOfItem(atPath: FleetPaths.socket.path),
       let mode = (attrs[.posixPermissions] as? NSNumber)?.int16Value {
        check("socket permissions", mode == 0o600, String(format: "%03o (must be 600)", mode))
    }

    let agentLoaded = Shell.run("/bin/launchctl", ["print", "gui/\(getuid())/\(FleetPaths.agentLabel)"], timeout: 5)
    check("launchd agent", agentLoaded.succeeded,
          agentLoaded.succeeded ? FleetPaths.agentLabel : "not loaded — run Scripts/install-agent.sh")

    // launchd throttles restarts (ThrottleInterval), so a controller that is simply
    // coming back up looks identical to a broken one for ~10 seconds. Waiting is
    // the difference between a useful diagnosis and a false alarm.
    var pong = (try? UnixSocketClient.send(RPCRequest(op: .ping), timeout: 4))?.daemon
    if pong == nil && agentLoaded.succeeded {
        print("  … controller not answering; waiting for a launchd restart (throttled up to 12s)")
        for _ in 0..<12 {
            usleep(1_000_000)
            if let daemon = (try? UnixSocketClient.send(RPCRequest(op: .ping), timeout: 2))?.daemon {
                pong = daemon
                break
            }
        }
    }
    if let daemon = pong {
        check("controller", true, "v\(daemon.version) pid \(daemon.pid), up \(Fmt.duration(daemon.uptime))")
        check("supervisor tick", daemon.lastTickAt != nil, "last tick \(Fmt.relative(daemon.lastTickAt))")
        check("reconciliation", daemon.lastReconcileAt != nil, "last sweep \(Fmt.relative(daemon.lastReconcileAt))")
    } else if agentLoaded.succeeded {
        let exitReason = agentLoaded.stdout
            .split(separator: "\n")
            .first { $0.contains("last exit reason") }?
            .trimmingCharacters(in: .whitespaces) ?? "unknown"
        check("controller", false, "agent is loaded but never answered — \(exitReason)")
        print("      check: tail -n 40 ~/Library/Logs/FleetConsole/fleetd.log")
    } else {
        check("controller", false, "not answering, and no launchd agent is loaded")
    }

    check("registry", FileManager.default.fileExists(atPath: FleetPaths.database.path), FleetPaths.database.path)
    check("config", FileManager.default.fileExists(atPath: FleetPaths.config.path), FleetPaths.config.path)
    check("log directory", FileManager.default.fileExists(atPath: FleetPaths.serviceLogs.path), FleetPaths.serviceLogs.path)
    check("tailscale CLI", TailscaleClient.executablePath != nil,
          TailscaleClient.executablePath ?? "not found — device probes will be limited")

    if let snapshot = (try? UnixSocketClient.send(RPCRequest(op: .snapshot), timeout: 6))?.snapshot {
        check("managed services", true, "\(snapshot.runningServices.count) running")
        // Unmanaged processes are a state of the machine, not a fault in the
        // install — reporting them as a failure here would contradict the whole
        // point of the attention rules and make `doctor` cry wolf on every run.
        let leaked = snapshot.unmanaged.filter { $0.formerServiceID != nil }
        print("  · \(pad("unmanaged processes", 26))\(snapshot.unmanaged.count) (informational — `fleetctl reconcile` to review)")
        if !leaked.isEmpty {
            check("leaked processes", false,
                  "\(leaked.count) outlived their registry record — these are real cleanup failures")
        }
    }

    print()
    print(problems == 0 ? "Everything checks out." : "\(problems) problem(s) found.")
    exit(problems == 0 ? 0 : 1)

case "config":
    if args.has("reload") {
        let response = send(RPCRequest(op: .reloadConfig))
        guard response.ok else { fail(response.error ?? "reload failed") }
        print("Configuration reloaded from \(FleetPaths.config.path)")
    } else if args.has("path") {
        print(FleetPaths.config.path)
    } else {
        guard let data = try? Data(contentsOf: FleetPaths.config),
              let text = String(data: data, encoding: .utf8) else {
            fail("cannot read \(FleetPaths.config.path)")
        }
        print(text)
    }

case "ignore":
    guard let command = args.positional.first else {
        fail("ignore needs a command name, e.g. `fleetctl ignore ssos-serve`")
    }
    let response = send(RPCRequest(op: .ignoreCommand, command: command), timeout: 30)
    guard response.ok else { fail(response.error ?? "could not update the allow-list") }
    print("'\(command)' is now an expected listener; it will not be flagged as unmanaged.")
    print("Edit ~/Library/Application Support/FleetConsole/config.json to undo.")

case "prune":
    let age = args.duration("older-than") ?? 3600
    let response = send(RPCRequest(op: .prune, ttlSec: age), timeout: 30)
    guard response.ok, let snapshot = response.snapshot else { fail(response.error ?? "prune failed") }
    print("Pruned stopped and crashed records older than \(Fmt.duration(age)).")
    print("\(snapshot.services.count) service record(s) remain. The event history is untouched.")

case "claim":
    guard let target = args.positional.first else {
        fail("claim needs an unmanaged process id or a pid — run `fleetctl reconcile` to list them")
    }
    let response = send(RPCRequest(op: .claim,
                                   ttlSec: args.duration("lease"),
                                   unmanagedID: target,
                                   friendlyName: args.first("name"),
                                   purpose: args.first("purpose"),
                                   agent: args.first("owner")), timeout: 30)
    guard response.ok, let service = response.service else { fail(response.error ?? "claim failed") }
    if args.has("json") {
        print(Codec.jsonString(service, pretty: true))
    } else {
        print("\(service.friendlyName) (\(service.shortID)): claimed pid \(service.pid.map(String.init) ?? "?")"
              + " for \(service.ownerAgent); lease expires \(Fmt.relative(service.leaseExpiresAt))")
        // Said every time, not buried in --help. The whole point of the verb is
        // that it changes what you can *see*, and someone who reads "claimed" as
        // "now under control" will be surprised by `stop` at the worst moment.
        print("The controller supervises it and will not signal it — it did not start it.")
    }

case "reconcile":
    let response = send(RPCRequest(op: .reconcile), timeout: 30)
    guard response.ok, let snapshot = response.snapshot else { fail(response.error ?? "reconcile failed") }
    if snapshot.unmanaged.isEmpty {
        print("No unmanaged listeners or dev-server processes found.")
    } else {
        print("\(snapshot.unmanaged.count) unmanaged process(es):")
        for process in snapshot.unmanaged {
            print("  pid \(process.pid) \(process.command) \(Fmt.ports(process.ports)) — \(process.reason.label)")
            print("      \(process.commandLine.prefix(140))")
        }
    }

default:
    fail("unknown command '\(subcommand)'. Run `fleetctl help`.")
}
