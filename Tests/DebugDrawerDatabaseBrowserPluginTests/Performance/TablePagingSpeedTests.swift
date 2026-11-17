// What a page of a large table costs. The plugin exists in debug builds only, so it is measured
// there; `--config=release` builds this target without it, and runs ReleaseInstallTests instead.
#if DEBUG
    @testable import DebugDrawerDatabaseBrowserPlugin
    import Foundation
    import SQLite3
    import Testing

    // Each page opens a connection, counts the matching rows and reads fifty at an offset. On a
    // 100,000-row table the last page takes about 2 ms and a search over every row about 15 ms on
    // an Apple silicon Mac in debug builds; the bound is many times that, so a loaded machine
    // passes and a page that reads the table more than once per call fails.
    @Suite(.timeLimit(.minutes(1)))
    struct TablePagingSpeedTests {
        @Test("The last page of a 100,000-row table, and a search over all of it, each read in under a second")
        func largeTable() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let url = folder.appending(path: "large.sqlite")
            var writer: OpaquePointer?
            try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
            defer { sqlite3_close(writer) }
            let setup = """
                PRAGMA journal_mode = WAL;
                CREATE TABLE events(id INTEGER PRIMARY KEY, name TEXT, value REAL);
                WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 100000)
                INSERT INTO events SELECT i, 'event ' || i, i * 0.5 FROM n;
                """
            try #require(sqlite3_exec(writer, setup, nil, nil, nil) == SQLITE_OK)
            let sut = SQLiteStore(url: url)
            let table = try #require(try await sut.schema().tables.first)
            let clock = ContinuousClock()

            let start = clock.now
            let last = try await sut.page(TablePageRequest(table: table, pageIndex: 1999))
            let lastElapsed = clock.now - start
            let searchStart = clock.now
            let search = try await sut.page(TablePageRequest(table: table, search: "event 9999"))
            let searchElapsed = clock.now - searchStart

            print("Databases: last page \(lastElapsed), search \(searchElapsed)")
            #expect(table.rowCount == 100_000)
            #expect(last.rows.rows.count == 50 && last.rows.rows.last?.first == .integer(100_000))
            #expect(search.matchingCount == 11)
            #expect(lastElapsed < .seconds(1))
            #expect(searchElapsed < .seconds(1))
        }
    }
#endif
