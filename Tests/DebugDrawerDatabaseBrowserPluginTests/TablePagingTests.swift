@testable import DebugDrawerDatabaseBrowserPlugin
import Foundation
import SQLite3
import Testing

@Suite(.timeLimit(.minutes(1)))
struct TablePagingTests {
    @Test("Pages hold 50 rows in rowid order; a page before the first reads the first and one past the last reads the last")
    func bounds() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "rows.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        let setup = """
        CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT);
        WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 101) INSERT INTO items SELECT i, 'item ' || i FROM n;
        """
        try #require(sqlite3_exec(writer, setup, nil, nil, nil) == SQLITE_OK)
        let sut = SQLiteStore(url: url)
        let table = try #require(try await sut.schema().tables.first)

        let first = try await sut.page(TablePageRequest(table: table, pageIndex: -1))
        let second = try await sut.page(TablePageRequest(table: table, pageIndex: 1))
        let last = try await sut.page(TablePageRequest(table: table, pageIndex: 7))

        #expect(first.pageIndex == 0)
        #expect(first.rows.rows.count == 50)
        #expect(first.rows.rows.first == [.integer(1), .text("item 1")])
        #expect(first.hasPreviousPage == false && first.hasNextPage)
        #expect(second.rows.rows.first?.first == .integer(51))
        #expect(second.rangeDescription == "Rows 51–100 of 101")
        #expect(last.pageIndex == 2)
        #expect(last.rows.rows == [[.integer(101), .text("item 101")]])
        #expect(last.pageCount == 3 && last.hasNextPage == false && last.hasPreviousPage)
        #expect(first.rows.columns == ["id", "name"])
    }

    @Test("An empty table has one empty page; exactly 50 rows fill one page, 51 a second")
    func edges() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "rows.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        let setup = """
        CREATE TABLE empty(id INTEGER PRIMARY KEY);
        CREATE TABLE fifty(id INTEGER PRIMARY KEY);
        CREATE TABLE fiftyone(id INTEGER PRIMARY KEY);
        WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 51) INSERT INTO fiftyone SELECT i FROM n;
        INSERT INTO fifty SELECT id FROM fiftyone WHERE id <= 50;
        """
        try #require(sqlite3_exec(writer, setup, nil, nil, nil) == SQLITE_OK)
        let sut = SQLiteStore(url: url)
        let tables = try await sut.schema().tables

        let empty = try await sut.page(TablePageRequest(table: tables[0], pageIndex: 3))
        let fifty = try await sut.page(TablePageRequest(table: tables[1]))
        let fiftyOne = try await sut.page(TablePageRequest(table: tables[2], pageIndex: 1))

        #expect(tables.map(\.name) == ["empty", "fifty", "fiftyone"])
        #expect(empty.pageIndex == 0 && empty.rows.rows.isEmpty && empty.pageCount == 1 && !empty.hasNextPage)
        #expect(empty.rangeDescription == "No rows")
        #expect(empty.rows.columns == ["id"])
        #expect(fifty.pageCount == 1 && !fifty.hasNextPage)
        #expect(fiftyOne.pageCount == 2 && fiftyOne.rows.rows == [[.integer(51)]])
    }

    @Test("Search looks in the text columns with bound LIKE patterns, ignoring ASCII case; % and _ match only themselves, and the count follows it")
    func search() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "people.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        let setup = """
        CREATE TABLE people(id INTEGER PRIMARY KEY, name VARCHAR(40), email TEXT, age INTEGER, notes);
        INSERT INTO people VALUES
            (1, 'Ana Lima', 'ana@example.com', 31, NULL),
            (2, 'Bo', 'bo@example.org', 42, '100% sure'),
            (3, 'Cy', NULL, 23, 'snake_case'),
            (4, 'Dee', 'dee@EXAMPLE.com', 31, 'snakeXcase');
        """
        try #require(sqlite3_exec(writer, setup, nil, nil, nil) == SQLITE_OK)
        let sut = SQLiteStore(url: url)
        let table = try #require(try await sut.schema().tables.first)

        let example = try await sut.page(TablePageRequest(table: table, search: "  example.COM "))
        let percent = try await sut.page(TablePageRequest(table: table, search: "%"))
        let underscore = try await sut.page(TablePageRequest(table: table, search: "e_c"))
        let number = try await sut.page(TablePageRequest(table: table, search: "31"))
        let quote = try await sut.page(TablePageRequest(table: table, search: "'; DROP TABLE people; --"))

        #expect(table.searchableColumns == ["name", "email", "notes"])
        #expect(example.rows.rows.map(\.first) == [.integer(1), .integer(4)])
        #expect(example.matchingCount == 2)
        #expect(example.searchedColumns == ["name", "email", "notes"])
        #expect(percent.rows.rows.map(\.first) == [.integer(2)])
        #expect(underscore.rows.rows.map(\.first) == [.integer(3)])
        #expect(number.matchingCount == 0)
        #expect(quote.matchingCount == 0)
        #expect(try await sut.run("SELECT count(*) FROM people").rows == [[.integer(4)]])
    }

    @Test("A blank search reads every row; a table with no text columns ignores the search")
    func blankSearch() throws {
        let numbers = StoreTable(
            name: "numbers", isView: false, columns: [StoreColumn(name: "n", declaredType: "INTEGER"), StoreColumn(name: "x", declaredType: "REAL")],
            rowCount: 3, hasRowID: true
        )
        let blank = TablePageRequest(table: numbers, search: "   ")
        let ignored = TablePageRequest(table: numbers, search: "7")

        #expect(blank.countSQL == #"SELECT count(*) FROM "numbers""#)
        #expect(ignored.pageSQL == #"SELECT * FROM "numbers" ORDER BY rowid LIMIT ? OFFSET ?"#)
        #expect(ignored.searchParameters.isEmpty)
    }

    @Test("The SQL quotes every identifier and binds every value; a table without a rowid isn't ordered by one")
    func sql() {
        let table = StoreTable(
            name: #"my "odd" table"#, isView: false,
            columns: [StoreColumn(name: "first name", declaredType: "TEXT"), StoreColumn(name: #"say "hi""#, declaredType: "")],
            rowCount: 1, hasRowID: false
        )
        let sut = TablePageRequest(table: table, pageIndex: 2, search: "50%")
        let expectedCount = #"SELECT count(*) FROM "my ""odd"" table" WHERE "first name" LIKE ? ESCAPE '\' OR "say ""hi""" LIKE ? ESCAPE '\'"#
        let expectedPage = #"SELECT * FROM "my ""odd"" table" WHERE "first name" LIKE ? ESCAPE '\' "#
            + #"OR "say ""hi""" LIKE ? ESCAPE '\' LIMIT ? OFFSET ?"#
        let expectedParameters: [SQLiteParameter] = [.text(#"%50\%%"#), .text(#"%50\%%"#)]

        #expect(sut.countSQL == expectedCount)
        #expect(sut.pageSQL == expectedPage)
        #expect(sut.searchParameters == expectedParameters)
        #expect(sut.clampedPageIndex(matching: 0) == 0)
        #expect(sut.clampedPageIndex(matching: 150) == 2)
        #expect(sut.clampedPageIndex(matching: 101) == 2)
        #expect(sut.clampedPageIndex(matching: 100) == 1)
    }

    @Test("Columns are searched by SQLite's affinity: TEXT, CHAR and CLOB and untyped ones, not INT, REAL or BLOB", arguments: [
        ("TEXT", true), ("VARCHAR(255)", true), ("NCHAR", true), ("CLOB", true), ("", true),
        ("INTEGER", false), ("CHARINT", false), ("REAL", false), ("BLOB", false), ("NUMERIC", false), ("DATETIME", false)
    ])
    func affinity(declaredType: String, isSearchable: Bool) {
        let actual = StoreColumn(name: "c", declaredType: declaredType).isSearchable

        #expect(actual == isSearchable)
    }
}
