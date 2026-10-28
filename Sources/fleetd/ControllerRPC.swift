import Foundation
import FleetCore

// The wire protocol. Split from Controller.swift so the state machine and the
// switch that dispatches into it are not the same file.
//
// The cost: the members reached for below are `internal` rather than `private`.
// fleetd is a seven-file executable, so that is module-private either way.

extension Controller {

    // MARK: - Connection handling

    func handleConnection(_ conn: SocketConnection) {
        defer {
            queue.sync { _ = subscribers.removeValue(forKey: ObjectIdentifier(conn)) }
            conn.close()
        }
        while true {
            let line: Data?
            do {
                line = try conn.readLine()
            } catch {
                FleetLog.debug("connection read error: \(error.localizedDescription)")
                return
            }
            guard let line else { return }

            let request: RPCRequest
            do {
                request = try Codec.decode(RPCRequest.self, from: line)
            } catch {
                try? conn.writeJSON(RPCResponse.failure("malformed request: \(error.localizedDescription)"))
                continue
            }

            if request.op == .subscribe {
                queue.sync { subscribers[ObjectIdentifier(conn)] = conn }
                let snapshot = queue.sync { makeSnapshot() }
                try? conn.writeJSON(RPCResponse(ok: true, snapshot: snapshot))
                continue    // further pushes come from broadcastSnapshot()
            }

            let response = handle(request)
            do {
                try conn.writeJSON(response)
            } catch {
                return
            }
        }
    }

    // MARK: - Answer shapes
    //
    // Three shapes cover every verb. A mutating verb that forgets its broadcast
    // leaves every open dashboard stale until the next supervisor tick, so the
    // broadcast belongs in the shape rather than in ten copies of it.

    /// Anything that throws answers with the error's own description.
    private func answering(_ build: () throws -> RPCResponse) -> RPCResponse {
        do {
            return try build()
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// On the state queue, broadcast, answer with the record. Every verb that
    /// changes one service.
    private func answeringWithRecord(_ body: () throws -> ServiceRecord) -> RPCResponse {
        answering {
            let record = try queue.sync(execute: body)
            broadcastSnapshot()
            return RPCResponse(ok: true, service: record)
        }
    }

    /// On the state queue, broadcast, answer with a fresh snapshot. Every verb
    /// that changes the fleet rather than one service.
    private func answeringWithSnapshot(_ body: () throws -> Void) -> RPCResponse {
        answering {
            try queue.sync(execute: body)
            broadcastSnapshot()
            return RPCResponse(ok: true, snapshot: queue.sync { makeSnapshot() })
        }
    }

    // MARK: - Dispatch

    func handle(_ request: RPCRequest) -> RPCResponse {
        switch request.op {
        case .ping:
            return RPCResponse(ok: true, daemon: queue.sync { daemon })

        case .snapshot:
            return RPCResponse(ok: true, snapshot: queue.sync { makeSnapshot() })

        case .subscribe:
            return RPCResponse.failure("subscribe is handled per-connection")

        case .launch:
            guard let launchRequest = request.launch else {
                return .failure("launch requires a request body")
            }
            return answeringWithRecord { try self.launch(launchRequest) }

        case .renew:
            guard let id = request.serviceID else { return .failure("renew requires a service id") }
            return answeringWithRecord { try self.renew(id, ttl: request.ttlSec) }

        case .stop:
            guard let id = request.serviceID else { return .failure("stop requires a service id") }
            return answeringWithRecord {
                let resolved = try self.resolveID(id)
                guard let record = self.services[resolved] else { throw FleetError.notFound(id) }
                guard !record.state.isTerminal else {
                    throw FleetError.rejected("\(record.friendlyName) is already \(record.state.rawValue)")
                }
                try self.requireSignallable(record)
                self.beginStop(record, reason: request.reason ?? "requested by operator",
                               requestedBy: "operator")
                return self.services[resolved] ?? record
            }

        case .restart:
            guard let id = request.serviceID else { return .failure("restart requires a service id") }
            // Not `answeringWithRecord`: `restart` is stop-then-relaunch and owns
            // its own queue hops, so it must not be wrapped in another `sync`.
            return answering {
                let record = try self.restart(id, reason: request.reason ?? "requested by operator")
                broadcastSnapshot()
                return RPCResponse(ok: true, service: record)
            }

        case .events:
            return answering {
                let events = try queue.sync { () -> [ServiceEvent] in
                    // An unknown id must fail loudly. Silently widening to the global
                    // log would answer a question nobody asked.
                    let resolved = try request.serviceID.map { try self.resolveID($0) }
                    return try self.registry.events(serviceID: resolved,
                                                    limit: min(request.limit ?? 200, 2000))
                }
                return RPCResponse(ok: true, events: events)
            }

        case .logs:
            guard let id = request.serviceID else { return .failure("logs requires a service id") }
            return answering {
                let chunk = try queue.sync {
                    try self.tailLog(id, stream: request.stream ?? "out",
                                     maxBytes: min(request.maxBytes ?? 64_000, 1_000_000))
                }
                return RPCResponse(ok: true, logs: chunk)
            }

        case .claim:
            guard let target = request.unmanagedID,
                  !target.trimmingCharacters(in: .whitespaces).isEmpty else {
                return .failure("claim requires an unmanaged process id or a pid")
            }
            // Captured off the state queue and passed in, so the verification and
            // the record are built from one table rather than two moments.
            let table = ProcessTable.capture()
            return answeringWithRecord {
                try self.claim(unmanagedID: target,
                          friendlyName: request.friendlyName,
                          owner: request.agent,
                          purpose: request.purpose,
                          ttl: request.ttlSec,
                          table: table)
            }

        case .reconcile:
            let table = ProcessTable.capture()
            return answeringWithSnapshot { self.runReconcile(table: table) }

        case .refreshDevices:
            // No broadcast: `probeDevices` pushes its own once the probe lands.
            probeDevices()
            return RPCResponse(ok: true, snapshot: queue.sync { makeSnapshot() })

        case .pause, .resume, .kill:
            guard let id = request.serviceID else {
                return .failure("\(request.op.rawValue) requires a service id")
            }
            return answeringWithRecord {
                switch request.op {
                case .pause: return try self.pause(id)
                case .resume: return try self.resume(id)
                default: return try self.forceKill(id, reason: request.reason ?? "requested by operator")
                }
            }

        case .postMessage:
            guard let agent = request.agent, !agent.isEmpty else {
                return .failure("a message needs --agent")
            }
            guard let body = request.body, !body.trimmingCharacters(in: .whitespaces).isEmpty else {
                return .failure("a message needs --message")
            }
            return answering {
                let stored = try queue.sync { () -> AgentMessage in
                    let service = try request.serviceID.flatMap { try self.registry.resolve(idOrPrefix: $0) }
                    let message = AgentMessage(agent: agent,
                                               serviceID: service?.id,
                                               serviceName: service?.friendlyName,
                                               kind: request.kind ?? .status,
                                               body: body,
                                               needsReply: request.needsReply ?? false)
                    let saved = try self.registry.post(message)
                    try self.registry.append(.messagePosted, service: service,
                                             detail: "\(agent) [\(saved.kind.rawValue)]"
                                                 + (saved.needsReply ? " (awaiting reply)" : "")
                                                 + ": \(body.prefix(160))")
                    return saved
                }
                broadcastSnapshot()
                return RPCResponse(ok: true, message: stored)
            }

        case .messages:
            return answering {
                let list = try queue.sync {
                    try self.registry.messages(agent: request.agent,
                                               limit: min(request.limit ?? 100, 1000),
                                               unansweredOnly: request.unansweredOnly ?? false)
                }
                return RPCResponse(ok: true, messages: list)
            }

        case .reply:
            guard let messageID = request.messageID else { return .failure("reply requires a message id") }
            guard let body = request.body, !body.trimmingCharacters(in: .whitespaces).isEmpty else {
                return .failure("reply requires text")
            }
            return answering {
                let updated = try queue.sync { () -> AgentMessage in
                    let answered = try self.registry.reply(to: messageID, with: body)
                    try self.registry.append(.messageAnswered, service: nil,
                                             detail: "answered \(answered.agent) message \(messageID): \(body.prefix(160))")
                    return answered
                }
                broadcastSnapshot()
                return RPCResponse(ok: true, message: updated)
            }

        case .markSeen:
            // Answers bare: the caller knows which ids it marked, and the
            // dashboards get the change by broadcast.
            return answering {
                try queue.sync {
                    let ids: [Int64]
                    if let single = request.messageID {
                        ids = [single]
                    } else {
                        ids = try self.self.registry.messages(limit: 200).filter { $0.seenAt == nil }.map(\.id)
                    }
                    try self.registry.markSeen(ids)
                }
                broadcastSnapshot()
                return RPCResponse(ok: true)
            }

        case .ignoreCommand:
            guard let command = request.command,
                  !command.trimmingCharacters(in: .whitespaces).isEmpty else {
                return .failure("ignoreCommand requires a command name")
            }
            // Its own catch, for its own message: "could not update config" says
            // the allow-list was not written; an error from inside save() does not.
            do {
                try queue.sync {
                    guard !self.config.ignoredListenerCommands.contains(command) else { return }
                    self.config.ignoredListenerCommands.append(command)
                    try self.config.save()
                    try self.registry.append(.registered, service: nil,
                                             detail: "'\(command)' added to the expected-listener allow-list by the operator")
                }
                let table = ProcessTable.capture()
                return answeringWithSnapshot { self.runReconcile(table: table) }
            } catch {
                return .failure("could not update config: \(error.localizedDescription)")
            }

        case .prune:
            // Terminal service rows only. The event log is append-only and is
            // never touched by this — the audit trail outlives the records.
            let age = request.ttlSec ?? 3600
            return answeringWithSnapshot {
                try self.registry.pruneTerminated(olderThan: age)
                let keep = Set(try self.registry.services().map(\.id))
                self.services = self.services.filter { keep.contains($0.key) }
            }

        case .reloadConfig:
            do {
                let fresh = try FleetConfig.load()
                queue.sync {
                    config = fresh
                    daemon.tickIntervalSec = fresh.supervisorTickSec
                }
                probeDevices()
                return RPCResponse(ok: true, snapshot: queue.sync { makeSnapshot() })
            } catch {
                return .failure("could not reload config: \(error.localizedDescription)")
            }
        }
    }
}
