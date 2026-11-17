@testable import DebugDrawerDatabaseBrowserPlugin
import Foundation
import SQLite3
import Testing

// Each test builds a real store in a temporary folder with a connection of its own, standing in
// for the app's, and reads it with the browser's.
@Suite(.timeLimit(.minutes(1)))
struct ReadOnlyGuardTests {
    @Test("A WAL store reads its committed rows while another connection holds an open write transaction")
    func readsBesideWriter() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "orders.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        let setup = "PRAGMA journal_mode = WAL; CREATE TABLE orders(id INTEGER PRIMARY KEY, note TEXT); INSERT INTO orders(note) VALUES ('a'), ('b');"
        try #require(sqlite3_exec(writer, setup, nil, nil, nil) == SQLITE_OK)
        try #require(sqlite3_exec(writer, "BEGIN EXCLUSIVE; INSERT INTO orders(note) VALUES ('not committed');", nil, nil, nil) == SQLITE_OK)
        let sut = SQLiteStore(url: url)
        let expected: [[SQLiteValue]] = [[.text("a")], [.text("b")]]

        let actual = try await sut.run("SELECT note FROM orders ORDER BY id")

        #expect(actual.rows == expected)
        #expect(sqlite3_exec(writer, "COMMIT", nil, nil, nil) == SQLITE_OK)
    }

    @Test("Statements that write, attach or change a setting are refused by the authorizer, and change nothing", arguments: [
        "INSERT INTO orders(note) VALUES ('x')",
        "UPDATE orders SET note = 'x'",
        "DELETE FROM orders",
        "ATTACH DATABASE ':memory:' AS other",
        "PRAGMA journal_mode = DELETE",
        "PRAGMA query_only = OFF",
        "CREATE TABLE more(x)",
        "DROP TABLE orders",
        "BEGIN",
        "REINDEX",
        "ANALYZE"
    ])
    func refused(sql: String) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "orders.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        // The index gives REINDEX something to do; with none it compiles to nothing.
        let setup = """
        PRAGMA journal_mode = WAL; CREATE TABLE orders(id INTEGER PRIMARY KEY, note TEXT);
        CREATE INDEX orders_note ON orders(note); INSERT INTO orders(note) VALUES ('a');
        """
        try #require(sqlite3_exec(writer, setup, nil, nil, nil) == SQLITE_OK)
        let sut = SQLiteStore(url: url)

        let actual: DatabaseError? = await {
            do throws(DatabaseError) {
                _ = try await sut.run(sql)
                return nil
            } catch {
                return error
            }
        }()

        guard case .refused = actual else {
            Issue.record("Expected the authorizer to refuse \(sql), got \(String(describing: actual))")
            return
        }
        let rows = try await sut.run("SELECT id, note FROM orders")
        let schema = try await sut.run("SELECT count(*) FROM sqlite_master")
        #expect(rows.rows == [[.integer(1), .text("a")]])
        #expect(schema.rows == [[.integer(2)]])
        #expect(try Data(contentsOf: url)[18 ... 19] == Data([2, 2]))
    }

    @Test("A statement the authorizer has no say over but that writes, VACUUM, is refused by sqlite3_stmt_readonly")
    func vacuumRefused() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "orders.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        try #require(sqlite3_exec(writer, "CREATE TABLE orders(id INTEGER PRIMARY KEY)", nil, nil, nil) == SQLITE_OK)
        let sut = SQLiteStore(url: url)

        await #expect(throws: DatabaseError.writes) {
            try await sut.run("VACUUM")
        }
    }

    @Test("A second statement after the first is refused, whether it reads or writes; trailing semicolons and comments are not one")
    func oneStatement() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "orders.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        try #require(sqlite3_exec(writer, "CREATE TABLE orders(id INTEGER PRIMARY KEY); INSERT INTO orders VALUES (1);", nil, nil, nil) == SQLITE_OK)
        let sut = SQLiteStore(url: url)
        let expected: [[SQLiteValue]] = [[.integer(1)]]

        let actual = try await sut.run("SELECT id FROM orders;  ; -- done\n/* really */")

        #expect(actual.rows == expected)
        await #expect(throws: DatabaseError.multipleStatements) { try await sut.run("SELECT 1; SELECT 2") }
        await #expect(throws: DatabaseError.multipleStatements) { try await sut.run("SELECT 1; DELETE FROM orders") }
        await #expect(throws: DatabaseError.multipleStatements) { try await sut.run("SELECT 1; nonsense") }
        await #expect(throws: DatabaseError.emptyQuery) { try await sut.run("  -- nothing\n") }
        #expect(try await sut.run("SELECT count(*) FROM orders").rows == expected)
    }

    @Test("After the browser's refused writes and its reads, PRAGMA integrity_check on the store returns ok")
    func integrityAfterwards() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "orders.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        let setup = "PRAGMA journal_mode = WAL; CREATE TABLE orders(id INTEGER PRIMARY KEY, note TEXT); INSERT INTO orders(note) VALUES ('a'), ('b');"
        try #require(sqlite3_exec(writer, setup, nil, nil, nil) == SQLITE_OK)
        try #require(sqlite3_exec(writer, "BEGIN; INSERT INTO orders(note) VALUES ('c');", nil, nil, nil) == SQLITE_OK)
        let sut = SQLiteStore(url: url)
        for sql in ["DELETE FROM orders", "PRAGMA journal_mode = DELETE", "SELECT 1; DROP TABLE orders", "VACUUM"] {
            _ = try? await sut.run(sql)
        }
        _ = try await sut.schema()
        _ = try await sut.page(TablePageRequest(table: try #require(try await sut.schema().tables.first)))
        try #require(sqlite3_exec(writer, "COMMIT", nil, nil, nil) == SQLITE_OK)
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(writer, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }

        try #require(sqlite3_step(statement) == SQLITE_ROW)
        let actual = String(cString: try #require(sqlite3_column_text(statement, 0)))

        #expect(actual == "ok")
    }

    @Test("Once the browser has read, the writer's TRUNCATE checkpoint succeeds and empties the WAL: it holds no read transaction")
    func checkpointAfterwards() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "orders.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        let setup = """
        PRAGMA journal_mode = WAL; PRAGMA wal_autocheckpoint = 0;
        CREATE TABLE orders(id INTEGER PRIMARY KEY, note TEXT);
        WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 500) INSERT INTO orders(note) SELECT 'note ' || i FROM n;
        """
        try #require(sqlite3_exec(writer, setup, nil, nil, nil) == SQLITE_OK)
        let wal = url.path(percentEncoded: false) + "-wal"
        let walBefore = try #require(try FileManager.default.attributesOfItem(atPath: wal)[.size] as? Int)
        try #require(walBefore > 0)
        let sut = SQLiteStore(url: url)
        let schema = try await sut.schema()
        _ = try await sut.page(TablePageRequest(table: try #require(schema.tables.first), pageIndex: 3, search: "note"))
        _ = try await sut.run("SELECT count(*) FROM orders")
        var logFrames: Int32 = 0
        var checkpointed: Int32 = 0

        let actual = sqlite3_wal_checkpoint_v2(writer, nil, SQLITE_CHECKPOINT_TRUNCATE, &logFrames, &checkpointed)

        #expect(actual == SQLITE_OK)
        #expect(try FileManager.default.attributesOfItem(atPath: wal)[.size] as? Int == 0)
    }

    @Test("A connection that holds a read transaction does make the TRUNCATE checkpoint fail, so the test above can tell")
    func checkpointBlockedByReader() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "orders.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        let setup = "PRAGMA journal_mode = WAL; PRAGMA wal_autocheckpoint = 0; "
            + "CREATE TABLE orders(id INTEGER PRIMARY KEY); INSERT INTO orders VALUES (1);"
        try #require(sqlite3_exec(writer, setup, nil, nil, nil) == SQLITE_OK)
        var reader: OpaquePointer?
        try #require(sqlite3_open_v2(url.path(percentEncoded: false), &reader, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(reader) }
        try #require(sqlite3_exec(reader, "BEGIN; SELECT count(*) FROM orders;", nil, nil, nil) == SQLITE_OK)
        try #require(sqlite3_exec(writer, "INSERT INTO orders VALUES (2)", nil, nil, nil) == SQLITE_OK)

        let actual = sqlite3_wal_checkpoint_v2(writer, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)

        #expect(actual == SQLITE_BUSY)
        #expect(sqlite3_exec(reader, "COMMIT", nil, nil, nil) == SQLITE_OK)
    }

    @Test("A rollback-journal store another connection holds an exclusive lock on fails with the busy error, once, after the busy timeout")
    func busy() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "orders.db")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        try #require(sqlite3_exec(writer, "PRAGMA journal_mode = DELETE; CREATE TABLE orders(id INTEGER PRIMARY KEY);", nil, nil, nil) == SQLITE_OK)
        try #require(sqlite3_exec(writer, "BEGIN EXCLUSIVE; INSERT INTO orders VALUES (1);", nil, nil, nil) == SQLITE_OK)
        let sut = SQLiteStore(url: url, busyTimeout: .milliseconds(20))

        await #expect(throws: DatabaseError.busy) { try await sut.run("SELECT count(*) FROM orders") }
        await #expect(throws: DatabaseError.busy) { try await sut.schema() }
        #expect(DatabaseError.busy.title == "Store busy, try again")

        try #require(sqlite3_exec(writer, "COMMIT", nil, nil, nil) == SQLITE_OK)
        #expect(try await sut.run("SELECT count(*) FROM orders").rows == [[.integer(1)]])
    }

    @Test("Each guard holds alone: the file opens read-only, query_only is on, and without the authorizer sqlite3_stmt_readonly refuses a write")
    func guardsIndependently() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "orders.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        try #require(sqlite3_exec(writer, "CREATE TABLE orders(id INTEGER PRIMARY KEY)", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(writer)
        let sut = try SQLiteConnection(readingAt: url.path(percentEncoded: false), busyTimeout: .milliseconds(250))

        sqlite3_set_authorizer(sut.handle, nil, nil)

        #expect(sqlite3_db_readonly(sut.handle, "main") == 1)
        #expect(try sut.query("PRAGMA query_only").rows == [[.integer(1)]])
        #expect(throws: DatabaseError.writes) { try sut.query("INSERT INTO orders VALUES (1)") }
        #expect(sqlite3_exec(sut.handle, "PRAGMA query_only = OFF", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(sut.handle, "INSERT INTO orders VALUES (1)", nil, nil, nil) & 0xFF == SQLITE_READONLY)
    }

    @Test("The authorizer allows reads, selects, functions and the table-describing pragmas, and denies everything else")
    func authorizerDecisions() {
        let allowed: [(Int32, String?)] = [
            (SQLITE_READ, nil), (SQLITE_SELECT, nil), (SQLITE_FUNCTION, nil),
            (SQLITE_PRAGMA, "table_info"), (SQLITE_PRAGMA, "TABLE_XINFO"), (SQLITE_PRAGMA, "index_list"),
            (SQLITE_PRAGMA, "index_info"), (SQLITE_PRAGMA, "index_xinfo"), (SQLITE_PRAGMA, "foreign_key_list")
        ]
        let denied: [(Int32, String?)] = [
            (SQLITE_INSERT, nil), (SQLITE_UPDATE, nil), (SQLITE_DELETE, nil), (SQLITE_ATTACH, nil), (SQLITE_DETACH, nil),
            (SQLITE_TRANSACTION, nil), (SQLITE_SAVEPOINT, nil), (SQLITE_CREATE_TABLE, nil), (SQLITE_DROP_TABLE, nil),
            (SQLITE_ALTER_TABLE, nil), (SQLITE_RECURSIVE, nil), (SQLITE_PRAGMA, "journal_mode"), (SQLITE_PRAGMA, "query_only"),
            (SQLITE_PRAGMA, "wal_checkpoint"), (SQLITE_PRAGMA, nil)
        ]

        let actualAllowed = allowed.map { SQLiteAuthorizer.decision(action: $0.0, pragma: $0.1) }
        let actualDenied = denied.map { SQLiteAuthorizer.decision(action: $0.0, pragma: $0.1) }

        #expect(actualAllowed == Array(repeating: SQLITE_OK, count: allowed.count))
        #expect(actualDenied == Array(repeating: SQLITE_DENY, count: denied.count))
    }

    @Test("A WAL store whose -shm file can't be made, in a folder that can't be written, says so in the model's typed error")
    @MainActor
    func sharedMemoryNotWritable() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stores = folder.appending(path: "Application Support", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stores, withIntermediateDirectories: true)
        defer {
            chmod(stores.path(percentEncoded: false), 0o755)
            try? FileManager.default.removeItem(at: folder)
        }
        let url = stores.appending(path: "orders.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        try #require(sqlite3_exec(writer, "PRAGMA journal_mode = WAL; CREATE TABLE orders(id INTEGER PRIMARY KEY);", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(writer)
        try? FileManager.default.removeItem(atPath: url.path(percentEncoded: false) + "-wal")
        try? FileManager.default.removeItem(atPath: url.path(percentEncoded: false) + "-shm")
        try #require(chmod(stores.path(percentEncoded: false), 0o555) == 0)
        let locations = FakeStoreLocations(applicationSupport: stores)
        let sut = DatabaseBrowserModel(discovery: StoreDiscovery(locations: locations, additionalDirectories: []))

        await sut.refresh()

        let listing = try #require(sut.listings.first)
        #expect(listing.store.journalMode == .wal)
        #expect(listing.store.canWriteSharedMemory == false)
        #expect(listing.schema == .failure(.sharedMemoryNotWritable))
    }
}
