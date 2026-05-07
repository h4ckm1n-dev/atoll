import CSQLiteShim
import Foundation
import SQLite3
import Testing
@testable import AtollCore

struct WarpSQLiteHardeningTests {
    /// Sanity check that the C shim wrapping `sqlite3_db_config(int)` is
    /// callable from Swift. This is the path AtollCore uses to apply the
    /// DEFENSIVE/TRUSTED_SCHEMA/DQS hardening flags after every read-only
    /// open of Warp's SQLite database.
    @Test
    func sqliteShimAppliesIntFlags() {
        var db: OpaquePointer?
        let path = ":memory:"
        let flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let openResult = sqlite3_open_v2(path, &db, flags, nil)
        #expect(openResult == SQLITE_OK)
        defer {
            if db != nil { sqlite3_close(db) }
        }

        let r1 = atoll_sqlite3_db_config_int(db, SQLITE_DBCONFIG_DEFENSIVE, 1)
        let r2 = atoll_sqlite3_db_config_int(db, SQLITE_DBCONFIG_TRUSTED_SCHEMA, 0)
        let r3 = atoll_sqlite3_db_config_int(db, SQLITE_DBCONFIG_DQS_DDL, 0)
        let r4 = atoll_sqlite3_db_config_int(db, SQLITE_DBCONFIG_DQS_DML, 0)

        #expect(r1 == SQLITE_OK)
        #expect(r2 == SQLITE_OK)
        #expect(r3 == SQLITE_OK)
        #expect(r4 == SQLITE_OK)
    }

    /// `boundedColumnText` must reject column values longer than
    /// `WarpSQLiteReader.maxColumnTextBytes` (4 KiB).
    @Test
    func boundedColumnTextRejectsOversizedValues() {
        var db: OpaquePointer?
        sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        defer { if db != nil { sqlite3_close(db) } }

        // Build a large string just over the cap.
        let huge = String(repeating: "A", count: WarpSQLiteReader.maxColumnTextBytes + 16)
        let escaped = huge.replacingOccurrences(of: "'", with: "''")
        let createSQL = "CREATE TABLE t (v TEXT); INSERT INTO t VALUES ('\(escaped)');"
        sqlite3_exec(db, createSQL, nil, nil, nil)

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT v FROM t LIMIT 1;", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }

        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        let result = WarpSQLiteReader.boundedColumnText(stmt: stmt, index: 0)
        #expect(result == nil, "oversized column value must be refused")
    }

    /// Short values still come through.
    @Test
    func boundedColumnTextAllowsSmallValues() {
        var db: OpaquePointer?
        sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        defer { if db != nil { sqlite3_close(db) } }
        sqlite3_exec(db, "CREATE TABLE t (v TEXT); INSERT INTO t VALUES ('ABCDEF');", nil, nil, nil)

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT v FROM t LIMIT 1;", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }

        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        let result = WarpSQLiteReader.boundedColumnText(stmt: stmt, index: 0)
        #expect(result == "ABCDEF")
    }
}
