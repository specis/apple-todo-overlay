import Foundation

enum SyncStateStore {

    private static let db = LocalDatabase.shared

    static func lastSyncDate(for provider: TaskSource) throws -> Date? {
        let rows = try db.query(
            "SELECT last_sync_at FROM sync_state WHERE provider = ?;",
            params: [provider.rawValue]
        )
        return rows.first?["last_sync_at"]?.dateValue
    }

    static func updateLastSync(for provider: TaskSource, date: Date, status: String = "ok", error: String? = nil) throws {
        try db.run("""
            INSERT INTO sync_state (provider, last_sync_at, last_status, last_error)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(provider) DO UPDATE SET
                last_sync_at = excluded.last_sync_at,
                last_status  = excluded.last_status,
                last_error   = excluded.last_error;
        """, params: [provider.rawValue, date, status, error])
    }

    static func updateCursor(for provider: TaskSource, cursor: String) throws {
        try db.run("""
            INSERT INTO sync_state (provider, last_cursor)
            VALUES (?, ?)
            ON CONFLICT(provider) DO UPDATE SET last_cursor = excluded.last_cursor;
        """, params: [provider.rawValue, cursor])
    }

    static func lastCursor(for provider: TaskSource) throws -> String? {
        let rows = try db.query(
            "SELECT last_cursor FROM sync_state WHERE provider = ?;",
            params: [provider.rawValue]
        )
        return rows.first?["last_cursor"]?.textValue
    }
}
