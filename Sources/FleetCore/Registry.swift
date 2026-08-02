import Foundation

/// The registry: managed services, an append-only event history, the unmanaged
/// cache and device state. Service/device rows keep indexed scalar columns for
/// queries plus a JSON payload for the full record, so the schema can evolve
/// without migrations for every new field.
///
/// The `events` table is protected by triggers that make UPDATE and DELETE fail —
/// history cannot be rewritten, including by a future bug in FleetConsole (T3).
public final class Registry {
    private let db: SQLiteDB

    /// `readOnly` is for readers that must work while the daemon is down (`fleetctl
    /// events --offline`): no schema work, no writes, nothing that could disturb a
    /// controller that comes back up while the reader is still open.
    public init(path: String = FleetPaths.database.path, readOnly: Bool = false) throws {
        if !readOnly { try FleetPaths.ensureDirectories() }
        self.db = try SQLiteDB(path: path, readOnly: readOnly)
        if !readOnly { try migrate() }
    }

    /// Forwarded so whoever owns the daemon lifecycle can bound the WAL and release
    /// the file explicitly — `deinit` never runs when the process leaves via exit().
    @discardableResult
    public func checkpoint(truncate: Bool = true) -> Bool {
        db.checkpoint(truncate: truncate)
    }

    public func close() { db.close() }

    private func migrate() throws {
        try db.exec("""
        CREATE TABLE IF NOT EXISTS services (
            id            TEXT PRIMARY KEY,
            friendly_name TEXT NOT NULL,
            owner_agent   TEXT NOT NULL,
            state         TEXT NOT NULL,
            pid           INTEGER,
            pgid          INTEGER,
            started_at    REAL NOT NULL,
            lease_expires_at REAL NOT NULL,
            updated_at    REAL NOT NULL,
            json          TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS services_state ON services(state);
        CREATE INDEX IF NOT EXISTS services_owner ON services(owner_agent);

        CREATE TABLE IF NOT EXISTS events (
            seq          INTEGER PRIMARY KEY AUTOINCREMENT,
            service_id   TEXT,
            service_name TEXT,
            ts           REAL NOT NULL,
            kind         TEXT NOT NULL,
            detail       TEXT NOT NULL,
            evidence     TEXT
        );
        CREATE INDEX IF NOT EXISTS events_service ON events(service_id, seq DESC);
        CREATE INDEX IF NOT EXISTS events_ts ON events(ts DESC);

        CREATE TRIGGER IF NOT EXISTS events_append_only_update
            BEFORE UPDATE ON events
            BEGIN SELECT RAISE(ABORT, 'events are append-only'); END;
        CREATE TRIGGER IF NOT EXISTS events_append_only_delete
            BEFORE DELETE ON events
            BEGIN SELECT RAISE(ABORT, 'events are append-only'); END;

        CREATE TABLE IF NOT EXISTS unmanaged (
            key        TEXT PRIMARY KEY,
            first_seen REAL NOT NULL,
            last_seen  REAL NOT NULL,
            json       TEXT NOT NULL
        );

        -- The agent mailbox. Bodies are append-only; `reply` is the single field
        -- that may be written after the fact, and only once.
        CREATE TABLE IF NOT EXISTS messages (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            agent      TEXT NOT NULL,
            service_id TEXT,
            service_name TEXT,
            kind       TEXT NOT NULL,
            body       TEXT NOT NULL,
            created_at REAL NOT NULL,
            needs_reply INTEGER NOT NULL DEFAULT 0,
            reply      TEXT,
            replied_at REAL,
            seen_at    REAL
        );
        CREATE INDEX IF NOT EXISTS messages_agent ON messages(agent, id DESC);

        CREATE TRIGGER IF NOT EXISTS messages_body_immutable
            BEFORE UPDATE OF body, agent, kind, created_at ON messages
            BEGIN SELECT RAISE(ABORT, 'message bodies are append-only'); END;
        CREATE TRIGGER IF NOT EXISTS messages_no_delete
            BEFORE DELETE ON messages
            BEGIN SELECT RAISE(ABORT, 'messages are append-only'); END;

        CREATE TABLE IF NOT EXISTS devices (
            id               TEXT PRIMARY KEY,
            last_reachable_at REAL,
            updated_at       REAL NOT NULL,
            json             TEXT NOT NULL
        );
        """)
    }

    // MARK: - Services

    public func upsert(_ service: ServiceRecord) throws {
        let json = String(data: try Codec.encode(service), encoding: .utf8) ?? "{}"
        try db.run("""
            INSERT INTO services (id, friendly_name, owner_agent, state, pid, pgid,
                                  started_at, lease_expires_at, updated_at, json)
            VALUES (?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
                friendly_name=excluded.friendly_name,
                owner_agent=excluded.owner_agent,
                state=excluded.state,
                pid=excluded.pid,
                pgid=excluded.pgid,
                lease_expires_at=excluded.lease_expires_at,
                updated_at=excluded.updated_at,
                json=excluded.json;
            """, [
                .text(service.id), .text(service.friendlyName), .text(service.ownerAgent),
                .text(service.state.rawValue), .opt(service.pid), .opt(service.pgid),
                .double(service.startedAt.timeIntervalSince1970),
                .double(service.leaseExpiresAt.timeIntervalSince1970),
                .double(Date().timeIntervalSince1970), .text(json),
            ])
    }

    public func service(id: String) throws -> ServiceRecord? {
        var found: ServiceRecord?
        try db.query("SELECT json FROM services WHERE id = ?;", [.text(id)]) { row in
            if let json = row.text(0), let data = json.data(using: .utf8) {
                found = try? Codec.decode(ServiceRecord.self, from: data)
            }
        }
        return found
    }

    /// Resolves a full id or a unique short-id prefix (what the CLI prints).
    public func resolve(idOrPrefix: String) throws -> ServiceRecord? {
        if let exact = try service(id: idOrPrefix) { return exact }
        var matches: [ServiceRecord] = []
        try db.query("SELECT json FROM services WHERE id LIKE ? || '%';", [.text(idOrPrefix)]) { row in
            if let json = row.text(0), let data = json.data(using: .utf8),
               let rec = try? Codec.decode(ServiceRecord.self, from: data) {
                matches.append(rec)
            }
        }
        if matches.count == 1 { return matches[0] }
        if matches.count > 1 {
            throw FleetError.rejected("id prefix '\(idOrPrefix)' is ambiguous (\(matches.count) matches)")
        }
        // Fall back to friendly name. Running services win; if none is running we
        // return the most recent terminal record, because "why did it crash" is
        // exactly when you reach for `fleetctl logs <name>`.
        let named = try services().filter { $0.friendlyName == idOrPrefix }
        let live = named.filter { !$0.state.isTerminal }
        if live.count == 1 { return live[0] }
        if live.count > 1 {
            throw FleetError.rejected("name '\(idOrPrefix)' matches \(live.count) running services; use the id")
        }
        return named.max { $0.startedAt < $1.startedAt }
    }

    public func services(includeTerminal: Bool = true) throws -> [ServiceRecord] {
        var result: [ServiceRecord] = []
        let sql = includeTerminal
            ? "SELECT json FROM services ORDER BY started_at DESC;"
            : "SELECT json FROM services WHERE state NOT IN ('stopped','crashed') ORDER BY started_at DESC;"
        try db.query(sql) { row in
            if let json = row.text(0), let data = json.data(using: .utf8),
               let rec = try? Codec.decode(ServiceRecord.self, from: data) {
                result.append(rec)
            }
        }
        return result
    }

    /// Terminal records older than `age` are pruned so the services table does not
    /// grow forever. The event history is never pruned — it is the audit trail.
    public func pruneTerminated(olderThan age: TimeInterval) throws {
        let cutoff = Date().addingTimeInterval(-age).timeIntervalSince1970
        try db.run("DELETE FROM services WHERE state IN ('stopped','crashed') AND updated_at < ?;",
                   [.double(cutoff)])
        // Bulk deletes are the single largest WAL producer in this file, so this is
        // where the WAL is actually reclaimed rather than left to grow.
        db.checkpoint(truncate: true)
    }

    // MARK: - Events (append-only)

    @discardableResult
    public func append(_ event: ServiceEvent) throws -> Int64 {
        let evidenceJSON = event.evidence.flatMap { String(data: (try? Codec.encode($0)) ?? Data(), encoding: .utf8) }
        return try db.run("""
            INSERT INTO events (service_id, service_name, ts, kind, detail, evidence)
            VALUES (?,?,?,?,?,?);
            """, [
                .opt(event.serviceID), .opt(event.serviceName),
                .double(event.ts.timeIntervalSince1970),
                .text(event.kind.rawValue), .text(event.detail), .opt(evidenceJSON),
            ])
    }

    @discardableResult
    public func append(_ kind: EventKind, service: ServiceRecord?, detail: String,
                       evidence: Evidence? = nil) throws -> Int64 {
        try append(ServiceEvent(serviceID: service?.id, serviceName: service?.friendlyName,
                                ts: Date(), kind: kind, detail: detail,
                                evidence: evidence ?? service?.evidence))
    }

    public func events(serviceID: String? = nil, limit: Int = 200) throws -> [ServiceEvent] {
        var result: [ServiceEvent] = []
        let sql: String
        let params: [SQLiteDB.Value]
        if let serviceID {
            sql = "SELECT seq, service_id, service_name, ts, kind, detail, evidence FROM events WHERE service_id = ? ORDER BY seq DESC LIMIT ?;"
            params = [.text(serviceID), .int(Int64(limit))]
        } else {
            sql = "SELECT seq, service_id, service_name, ts, kind, detail, evidence FROM events ORDER BY seq DESC LIMIT ?;"
            params = [.int(Int64(limit))]
        }
        try db.query(sql, params) { row in
            if let event = Self.decodeEvent(row) { result.append(event) }
        }
        return result
    }

    /// Most recent events restricted to a set of kinds. The daemon uses this to tell a
    /// clean shutdown from a generation that died without writing one.
    public func events(kinds: [EventKind], limit: Int = 20) throws -> [ServiceEvent] {
        guard !kinds.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: kinds.count).joined(separator: ",")
        var params: [SQLiteDB.Value] = kinds.map { .text($0.rawValue) }
        params.append(.int(Int64(limit)))
        var result: [ServiceEvent] = []
        try db.query("""
            SELECT seq, service_id, service_name, ts, kind, detail, evidence FROM events
            WHERE kind IN (\(placeholders)) ORDER BY seq DESC LIMIT ?;
            """, params) { row in
            if let event = Self.decodeEvent(row) { result.append(event) }
        }
        return result
    }

    /// Column order is fixed by the two SELECTs above; kept in one place so they
    /// cannot drift apart.
    private static func decodeEvent(_ row: SQLiteDB.Row) -> ServiceEvent? {
        guard let kindRaw = row.text(4), let kind = EventKind(rawValue: kindRaw) else { return nil }
        var evidence: Evidence?
        if let e = row.text(6), let data = e.data(using: .utf8) {
            evidence = try? Codec.decode(Evidence.self, from: data)
        }
        return ServiceEvent(seq: row.int(0) ?? 0,
                            serviceID: row.text(1),
                            serviceName: row.text(2),
                            ts: Date(timeIntervalSince1970: row.double(3) ?? 0),
                            kind: kind,
                            detail: row.text(5) ?? "",
                            evidence: evidence)
    }

    // MARK: - Unmanaged

    /// Merges this sweep's unmanaged set into the table, preserving `firstSeen` for keys
    /// we have seen before so "how long has this been leaking" survives restarts.
    ///
    /// Upsert plus a targeted delete, never DELETE-all-and-reinsert: with the latter a
    /// single sweep that saw nothing (a `ps`/`lsof` failure upstream used to look
    /// exactly like an empty machine) wiped every row, lost every `first_seen`, and the
    /// next good sweep re-emitted the whole list as brand-new `becameUnmanaged` events.
    public func syncUnmanaged(_ found: [UnmanagedProcess]) throws -> [UnmanagedProcess] {
        var existing: [String: Date] = [:]
        try db.query("SELECT key, first_seen FROM unmanaged;") { row in
            if let key = row.text(0), let ts = row.double(1) {
                existing[key] = Date(timeIntervalSince1970: ts)
            }
        }
        let foundKeys = Set(found.map(\.id))
        var merged: [UnmanagedProcess] = []
        try db.transaction {
            for var proc in found {
                if let first = existing[proc.id] { proc.firstSeen = first }
                let json = String(data: try Codec.encode(proc), encoding: .utf8) ?? "{}"
                try db.run("""
                    INSERT INTO unmanaged (key, first_seen, last_seen, json) VALUES (?,?,?,?)
                    ON CONFLICT(key) DO UPDATE SET
                        last_seen=excluded.last_seen,
                        json=excluded.json;
                    """,
                           [.text(proc.id),
                            .double(proc.firstSeen.timeIntervalSince1970),
                            .double(proc.lastSeen.timeIntervalSince1970),
                            .text(json)])
                merged.append(proc)
            }
            // Only keys this sweep genuinely did not see are dropped.
            for key in existing.keys where !foundKeys.contains(key) {
                try db.run("DELETE FROM unmanaged WHERE key = ?;", [.text(key)])
            }
        }
        return merged
    }

    public func unmanaged() throws -> [UnmanagedProcess] {
        var result: [UnmanagedProcess] = []
        try db.query("SELECT json FROM unmanaged ORDER BY first_seen ASC;") { row in
            if let json = row.text(0), let data = json.data(using: .utf8),
               let rec = try? Codec.decode(UnmanagedProcess.self, from: data) {
                result.append(rec)
            }
        }
        return result
    }

    // MARK: - Messages

    public func post(_ message: AgentMessage) throws -> AgentMessage {
        let id = try db.run("""
            INSERT INTO messages (agent, service_id, service_name, kind, body, created_at, needs_reply)
            VALUES (?,?,?,?,?,?,?);
            """, [.text(message.agent), .opt(message.serviceID), .opt(message.serviceName),
                  .text(message.kind.rawValue), .text(message.body),
                  .double(message.createdAt.timeIntervalSince1970),
                  .int(message.needsReply ? 1 : 0)])
        var stored = message
        stored.id = id
        return stored
    }

    public func messages(agent: String? = nil, limit: Int = 100,
                         unansweredOnly: Bool = false) throws -> [AgentMessage] {
        var sql = "SELECT id, agent, service_id, service_name, kind, body, created_at, needs_reply, reply, replied_at, seen_at FROM messages"
        var clauses: [String] = []
        var params: [SQLiteDB.Value] = []
        if let agent {
            clauses.append("agent = ?")
            params.append(.text(agent))
        }
        if unansweredOnly {
            clauses.append("needs_reply = 1 AND reply IS NULL")
        }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY id DESC LIMIT ?;"
        params.append(.int(Int64(limit)))

        var result: [AgentMessage] = []
        try db.query(sql, params) { row in
            guard let agentName = row.text(1), let kindRaw = row.text(4),
                  let kind = MessageKind(rawValue: kindRaw), let body = row.text(5) else { return }
            result.append(AgentMessage(
                id: row.int(0) ?? 0,
                agent: agentName,
                serviceID: row.text(2),
                serviceName: row.text(3),
                kind: kind,
                body: body,
                createdAt: Date(timeIntervalSince1970: row.double(6) ?? 0),
                needsReply: (row.int(7) ?? 0) == 1,
                reply: row.text(8),
                repliedAt: row.double(9).map { Date(timeIntervalSince1970: $0) },
                seenAt: row.double(10).map { Date(timeIntervalSince1970: $0) }))
        }
        return result
    }

    /// A reply is written exactly once: answering twice would silently rewrite
    /// what the agent already read.
    public func reply(to id: Int64, with text: String) throws -> AgentMessage {
        var existing: AgentMessage?
        try db.query("SELECT reply FROM messages WHERE id = ?;", [.int(id)]) { row in
            existing = AgentMessage(id: id, agent: "", body: "", reply: row.text(0))
        }
        guard let existing else { throw FleetError.notFound("message \(id)") }
        guard existing.reply == nil else {
            throw FleetError.rejected("message \(id) has already been answered")
        }
        try db.run("UPDATE messages SET reply = ?, replied_at = ? WHERE id = ?;",
                   [.text(text), .double(Date().timeIntervalSince1970), .int(id)])
        guard let updated = try messages(limit: 1000).first(where: { $0.id == id }) else {
            throw FleetError.notFound("message \(id)")
        }
        return updated
    }

    public func markSeen(_ ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        for id in ids {
            try db.run("UPDATE messages SET seen_at = ? WHERE id = ? AND seen_at IS NULL;",
                       [.double(now), .int(id)])
        }
    }

    // MARK: - Devices

    public func upsert(_ device: DeviceRecord) throws {
        let json = String(data: try Codec.encode(device), encoding: .utf8) ?? "{}"
        try db.run("""
            INSERT INTO devices (id, last_reachable_at, updated_at, json) VALUES (?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
                last_reachable_at=excluded.last_reachable_at,
                updated_at=excluded.updated_at,
                json=excluded.json;
            """, [.text(device.id), .opt(device.lastReachableAt),
                  .double(Date().timeIntervalSince1970), .text(json)])
    }

    public func devices() throws -> [DeviceRecord] {
        var result: [DeviceRecord] = []
        try db.query("SELECT json FROM devices;") { row in
            if let json = row.text(0), let data = json.data(using: .utf8),
               let rec = try? Codec.decode(DeviceRecord.self, from: data) {
                result.append(rec)
            }
        }
        return result
    }
}
