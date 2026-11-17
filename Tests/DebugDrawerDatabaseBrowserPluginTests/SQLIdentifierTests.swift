@testable import DebugDrawerDatabaseBrowserPlugin
import Foundation
import SQLite3
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SQLIdentifierTests {
    @Test("An identifier is quoted in double quotes with its own quotes doubled", arguments: [
        ("orders", #""orders""#),
        (#"my "best" table"#, #""my ""best"" table""#),
        ("line items", #""line items""#),
        ("", #""""#),
        (#"""#, #""""""#),
        ("ünïcødé 表", #""ünïcødé 表""#)
    ])
    func quoting(name: String, expected: String) {
        let actual = name.quotedSQLIdentifier

        #expect(actual == expected)
    }

    @Test("Tables with quotes, spaces, unicode and SQL in their names are listed, counted, paged and searched")
    func nastyNames() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "nasty.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        let names = [#"say "hi""#, "line items", "ünïcødé 表", #"x"; DROP TABLE safe; --"#, "safe"]
        for name in names {
            let quoted = name.quotedSQLIdentifier
            let column = #"the "text""#.quotedSQLIdentifier
            let sql = "CREATE TABLE \(quoted)(id INTEGER PRIMARY KEY, \(column) TEXT); INSERT INTO \(quoted) VALUES (1, 'one'), (2, 'two');"
            try #require(sqlite3_exec(writer, sql, nil, nil, nil) == SQLITE_OK)
        }
        let sut = SQLiteStore(url: url)

        let tables = try await sut.schema().tables
        var pages: [TablePage] = []
        for table in tables {
            pages.append(try await sut.page(TablePageRequest(table: table, search: "tw")))
        }

        #expect(Set(tables.map(\.name)) == Set(names))
        #expect(tables.allSatisfy { $0.rowCount == 2 && $0.columns.map(\.name) == ["id", #"the "text""#] })
        #expect(pages.allSatisfy { $0.rows.rows == [[.integer(2), .text("two")]] && $0.matchingCount == 1 })
    }
}
