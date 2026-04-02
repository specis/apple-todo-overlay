import Foundation
import SQLite3

// MARK: - Errors

enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let m):   return "DB open failed: \(m)"
        case .prepareFailed(let m): return "DB prepare failed: \(m)"
        case .stepFailed(let m):   return "DB step failed: \(m)"
        }
    }
}

// MARK: - Value type

enum DatabaseValue {
    case integer(Int64)
    case real(Double)
    case text(String)
    case null

    var intValue: Int64?    { if case .integer(let v) = self { return v } ; return nil }
    var doubleValue: Double? { if case .real(let v) = self { return v } ; return nil }
    var textValue: String?  { if case .text(let v) = self { return v } ; return nil }
    var boolValue: Bool?    { intValue.map { $0 != 0 } }
    var dateValue: Date?    { intValue.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
}

typealias Row = [String: DatabaseValue]

// MARK: - LocalDatabase

final class LocalDatabase {

    static let shared = LocalDatabase()

    private var db: OpaquePointer?

    // SQLite requires copies of string values — SQLITE_TRANSIENT signals it should copy
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {}

    // MARK: - Lifecycle

    func open() throws {
        let url = try databaseURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw DatabaseError.openFailed(errorMessage())
        }

        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA foreign_keys = ON;")
        try runMigrations()
    }

    func close() {
        sqlite3_close(db)
        db = nil
    }

    // MARK: - Read

    func query(_ sql: String, params: [Any?] = []) throws -> [Row] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(errorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        bindParams(params, to: stmt)

        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: Row = [:]
            let count = sqlite3_column_count(stmt)
            for i in 0..<count {
                let key = String(cString: sqlite3_column_name(stmt, i))
                row[key] = value(from: stmt, at: i)
            }
            rows.append(row)
        }
        return rows
    }

    // MARK: - Write

    @discardableResult
    func run(_ sql: String, params: [Any?] = []) throws -> Int64 {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(errorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        bindParams(params, to: stmt)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(errorMessage())
        }
        return sqlite3_last_insert_rowid(db)
    }

    func execute(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errMsg) == SQLITE_OK else {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw DatabaseError.stepFailed(msg)
        }
    }

    // MARK: - Binding

    private func bindParams(_ params: [Any?], to stmt: OpaquePointer?) {
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case let v as Bool:   sqlite3_bind_int64(stmt, idx, v ? 1 : 0)
            case let v as Int:    sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64:  sqlite3_bind_int64(stmt, idx, v)
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case let v as Date:   sqlite3_bind_int64(stmt, idx, Int64(v.timeIntervalSince1970))
            default:              sqlite3_bind_null(stmt, idx)
            }
        }
    }

    private func value(from stmt: OpaquePointer?, at index: Int32) -> DatabaseValue {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_INTEGER: return .integer(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT:   return .real(sqlite3_column_double(stmt, index))
        case SQLITE_TEXT:    return .text(String(cString: sqlite3_column_text(stmt, index)))
        default:             return .null
        }
    }

    // MARK: - Helpers

    private func errorMessage() -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "no connection"
    }

    private func databaseURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("apple-todo-overlay", isDirectory: true)
            .appendingPathComponent("tasks.db")
    }

    // MARK: - Migrations

    private func runMigrations() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS db_version (
                version INTEGER NOT NULL
            );
        """)

        let rows = try query("SELECT version FROM db_version LIMIT 1;")
        let current = rows.first?["version"]?.intValue ?? 0

        if current < 1 { try migrateV1() ; try setVersion(1, previous: current) }
    }

    private func setVersion(_ version: Int64, previous: Int64) throws {
        if previous == 0 {
            try run("INSERT INTO db_version (version) VALUES (?);", params: [version])
        } else {
            try run("UPDATE db_version SET version = ?;", params: [version])
        }
    }

    // Version 1 — full initial schema (base + extensions combined)
    private func migrateV1() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS task_lists (
                id            TEXT PRIMARY KEY,
                name          TEXT NOT NULL,
                source        TEXT NOT NULL,
                external_id   TEXT,
                created_at    INTEGER NOT NULL,
                last_modified INTEGER NOT NULL,
                is_deleted    INTEGER NOT NULL DEFAULT 0
            );
        """)

        try execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id            TEXT PRIMARY KEY,
                list_id       TEXT,
                title         TEXT NOT NULL,
                notes         TEXT,
                due_date      INTEGER,
                completed     INTEGER NOT NULL DEFAULT 0,
                completed_at  INTEGER,
                source        TEXT NOT NULL,
                external_id   TEXT,
                created_at    INTEGER NOT NULL,
                last_modified INTEGER NOT NULL,
                sync_status   TEXT NOT NULL DEFAULT 'SYNCED',
                is_deleted    INTEGER NOT NULL DEFAULT 0,
                priority      TEXT NOT NULL DEFAULT 'NONE',
                FOREIGN KEY (list_id) REFERENCES task_lists(id)
            );
        """)

        try execute("""
            CREATE TABLE IF NOT EXISTS tags (
                id         TEXT PRIMARY KEY,
                name       TEXT NOT NULL,
                colour     TEXT NOT NULL DEFAULT '#888888',
                created_at INTEGER NOT NULL
            );
        """)

        try execute("""
            CREATE TABLE IF NOT EXISTS task_tags (
                task_id TEXT NOT NULL,
                tag_id  TEXT NOT NULL,
                PRIMARY KEY (task_id, tag_id),
                FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
                FOREIGN KEY (tag_id)  REFERENCES tags(id)  ON DELETE CASCADE
            );
        """)

        try execute("""
            CREATE TABLE IF NOT EXISTS sync_state (
                provider     TEXT PRIMARY KEY,
                last_sync_at INTEGER,
                last_cursor  TEXT,
                last_status  TEXT,
                last_error   TEXT
            );
        """)

        try execute("""
            CREATE TABLE IF NOT EXISTS sync_log (
                id          TEXT PRIMARY KEY,
                provider    TEXT NOT NULL,
                entity_type TEXT NOT NULL,
                entity_id   TEXT NOT NULL,
                action      TEXT NOT NULL,
                status      TEXT NOT NULL,
                message     TEXT,
                created_at  INTEGER NOT NULL
            );
        """)

        try execute("CREATE INDEX IF NOT EXISTS idx_tasks_due_date     ON tasks(due_date);")
        try execute("CREATE INDEX IF NOT EXISTS idx_tasks_completed    ON tasks(completed);")
        try execute("CREATE INDEX IF NOT EXISTS idx_tasks_sync_status  ON tasks(sync_status);")
        try execute("CREATE INDEX IF NOT EXISTS idx_tasks_list_id      ON tasks(list_id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_tasks_last_modified ON tasks(last_modified);")
        try execute("CREATE INDEX IF NOT EXISTS idx_tasks_priority     ON tasks(priority);")
        try execute("CREATE INDEX IF NOT EXISTS idx_task_tags_task_id  ON task_tags(task_id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_task_tags_tag_id   ON task_tags(tag_id);")
    }
}
