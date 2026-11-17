@testable import DebugDrawerDatabaseBrowserPlugin
import Foundation
import SQLite3
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SQLiteValueTests {
    @Test("Each storage class reads as its own value: NULL, integer, real, text with any characters, and a blob as its size and first 16 bytes")
    func reading() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "values.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        try #require(sqlite3_exec(writer, "CREATE TABLE t(v)", nil, nil, nil) == SQLITE_OK)
        let sut = SQLiteStore(url: url)
        let expected: [[SQLiteValue]] = [[
            .null, .integer(-9_223_372_036_854_775_808), .real(29.99), .text("é\u{0}x 表"),
            .blob(size: 20, prefix: Data((0 ..< 16).map { UInt8($0) })), .blob(size: 0, prefix: Data())
        ]]

        let sql = "SELECT NULL, -9223372036854775808, 29.99, 'é' || char(0) || 'x 表', x'000102030405060708090A0B0C0D0E0F10111213', x''"

        let actual = try await sut.run(sql)

        #expect(actual.rows == expected)
        #expect(actual.columns.count == 6)
    }

    @Test("Text that isn't well-formed UTF-8 still reads, its bad bytes as U+FFFD")
    func illFormedText() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "bad.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        try #require(sqlite3_exec(writer, "CREATE TABLE t(v)", nil, nil, nil) == SQLITE_OK)
        let sut = SQLiteStore(url: url)
        let expected: [[SQLiteValue]] = [[.text("a\u{FFFD}b")]]

        let actual = try await sut.run("SELECT CAST(x'61FF62' AS TEXT)")

        #expect(actual.rows == expected)
    }

    @Test("A cell shows NULL, integers in full, reals to 15 significant digits, text as it is, a blob as its size and first bytes",
          arguments: [
        (SQLiteValue.null, "NULL"),
        (.integer(42), "42"),
        (.integer(-7), "-7"),
        (.real(29.99), "29.99"),
        (.real(1e-7), "1e-07"),
        (.real(32.480000000000004), "32.48"),
        (.real(12), "12.0"),
        (.real(-0.5), "-0.5"),
        (.real(1e20), "1e+20"),
        (.real(.infinity), "inf"),
        (.text("Ana"), "Ana"),
        (.text(""), ""),
        (.blob(size: 0, prefix: Data()), "0 bytes"),
        (.blob(size: 1, prefix: Data([0xFF])), "1 byte · FF"),
        (.blob(size: 4, prefix: Data([0x89, 0x50, 0x4E, 0x47])), "4 bytes · 89 50 4E 47"),
        (.blob(size: 999, prefix: Data([0x89, 0x50])), "999 bytes · 89 50…")
    ])
    func displayText(value: SQLiteValue, expected: String) {
        let actual = value.displayText

        #expect(actual == expected)
    }

    @Test("A cell keeps to its first line and the character limit, ending in an ellipsis when it cuts")
    func cellText() {
        let long = SQLiteValue.text(String(repeating: "a", count: 41))
        let exact = SQLiteValue.text(String(repeating: "b", count: 40))
        let lines = SQLiteValue.text("first\nsecond")
        let crlf = SQLiteValue.text("one\r\ntwo")

        #expect(long.cellText(limit: 40) == String(repeating: "a", count: 40) + "…")
        #expect(exact.cellText(limit: 40) == String(repeating: "b", count: 40))
        #expect(lines.cellText(limit: 40) == "first…")
        #expect(crlf.cellText(limit: 40) == "one…")
        #expect(long.isCut(at: 40) && !exact.isCut(at: 40))
        #expect(SQLiteValue.null.cellText(limit: 2) == "NU…")
    }

    @Test("Each storage class names its type as typeof() does", arguments: [
        (SQLiteValue.null, "null"), (.integer(1), "integer"), (.real(1), "real"), (.text("a"), "text"), (.blob(size: 1, prefix: Data()), "blob")
    ])
    func typeName(value: SQLiteValue, expected: String) {
        #expect(value.typeName == expected)
    }
}
