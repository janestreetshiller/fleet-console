import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Minimal sqlite3 wrapper. No external dependencies: the registry must work on a
/// clean machine with nothing but the OS.
public final class SQLiteDB {
    private var handle: OpaquePointer?
    private let path: String

    public init(path: String, readOnly: Bool = false) throws {
        self.path = path
        var db: OpaquePointer?
        var flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        var rc = sqlite3_open_v2(path, &db, flags, nil)
        if rc != SQLITE_OK, readOnly {
            // Reading a WAL database needs a shared-memory file, and a read-only
            // connection cannot create one. Falling back to a read-write handle (never
            // CREATE) is the difference between "history is readable when the daemon is
            // down" and "the one moment you need it, you cannot have it".
            sqlite3_close_v2(db)
            db = nil
            flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
            rc = sqlite3_open_v2(path, &db, flags, nil)
        }
        guard rc == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close_v2(db)
            throw FleetError.storage("open \(path): \(msg)")
        }
        self.handle = db
        sqlite3_busy_timeout(db, 3000)
        if !readOnly {
            try exec("PRAGMA journal_mode=WAL;")
            // The 1000-page default lets the WAL grow to ~4 MB before SQLite trims it,
            // and nothing here ever ran a checkpoint of its own — a 295 KB registry was
            // observed carrying a 3.3 MB WAL. 256 pages caps it around 1 MB.
            try exec("PRAGMA wal_autocheckpoint=256;")
            // NORMAL is the durability point WAL was designed for: a process crash
            // cannot corrupt the file, only lose the last commits — and every writer
            // here is a controller that re-verifies its state on startup anyway.
            try exec("PRAGMA synchronous=NORMAL;")
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
        try exec("PRAGMA foreign_keys=ON;")
    }

    deinit { if let handle { sqlite3_close_v2(handle) } }

    /// Applies WAL frames back into the database. `truncate` also resets the WAL file
    /// to zero bytes instead of leaving already-applied frames on disk forever.
    @discardableResult
    public func checkpoint(truncate: Bool = false) -> Bool {
        guard let handle else { return false }
        let mode = truncate ? SQLITE_CHECKPOINT_TRUNCATE : SQLITE_CHECKPOINT_PASSIVE
        return sqlite3_wal_checkpoint_v2(handle, nil, mode, nil, nil) == SQLITE_OK
    }

    /// Explicit, idempotent close. `deinit` is not a shutdown path here: fleetd always
    /// leaves through exit()/fatalError, so without this the WAL was simply abandoned
    /// for the next process to inherit.
    public func close() {
        guard let handle else { return }
        checkpoint(truncate: true)
        sqlite3_close_v2(handle)
        self.handle = nil
    }

    private var errorMessage: String {
        guard let handle else { return "closed" }
        return String(cString: sqlite3_errmsg(handle))
    }

    public func exec(_ sql: String) throws {
        guard let handle else { throw FleetError.storage("db closed") }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(err)
            throw FleetError.storage("\(msg) — while executing: \(sql.prefix(120))")
        }
    }

    public enum Value {
        case text(String)
        case int(Int64)
        case double(Double)
        case null
    }

    @discardableResult
    public func run(_ sql: String, _ params: [Value] = []) throws -> Int64 {
        guard let handle else { throw FleetError.storage("db closed") }
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw FleetError.storage("\(errorMessage) — \(sql.prefix(120))")
        }
        return sqlite3_last_insert_rowid(handle)
    }

    public func query(_ sql: String, _ params: [Value] = [],
                      _ row: (Row) throws -> Void) throws {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                try row(Row(stmt: stmt))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw FleetError.storage("\(errorMessage) — \(sql.prefix(120))")
            }
        }
    }

    private func prepare(_ sql: String, _ params: [Value]) throws -> OpaquePointer? {
        guard let handle else { throw FleetError.storage("db closed") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw FleetError.storage("prepare failed: \(errorMessage) — \(sql.prefix(120))")
        }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
        return stmt
    }

    public struct Row {
        let stmt: OpaquePointer?

        public func text(_ index: Int32) -> String? {
            guard let c = sqlite3_column_text(stmt, index) else { return nil }
            return String(cString: c)
        }

        public func int(_ index: Int32) -> Int64? {
            guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
            return sqlite3_column_int64(stmt, index)
        }

        public func double(_ index: Int32) -> Double? {
            guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
            return sqlite3_column_double(stmt, index)
        }
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE;")
        do {
            let result = try body()
            try exec("COMMIT;")
            return result
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }
}

extension SQLiteDB.Value {
    public static func opt(_ s: String?) -> SQLiteDB.Value { s.map { .text($0) } ?? .null }
    public static func opt(_ i: Int32?) -> SQLiteDB.Value { i.map { .int(Int64($0)) } ?? .null }
    public static func opt(_ d: Date?) -> SQLiteDB.Value { d.map { .double($0.timeIntervalSince1970) } ?? .null }
}
