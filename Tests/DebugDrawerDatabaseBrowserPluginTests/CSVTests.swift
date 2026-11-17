@testable import DebugDrawerDatabaseBrowserPlugin
import Foundation
import Testing

@Suite
struct CSVTests {
    @Test("CSV has a header of column names and a CRLF-ended line per row; NULL is empty and a blob is its summary")
    func plain() {
        let sut = ResultSet(
            columns: ["id", "name", "price", "notes", "thumbnail"],
            rows: [
                [.integer(1), .text("Mug"), .real(9.5), .null, .blob(size: 2, prefix: Data([0xCA, 0xFE]))],
                [.integer(2), .text("Plate"), .real(12), .text("ok"), .null]
            ]
        )
        let expected = "id,name,price,notes,thumbnail\r\n1,Mug,9.5,,2 bytes · CA FE\r\n2,Plate,12.0,ok,\r\n"

        let actual = sut.csv

        #expect(actual == expected)
    }

    @Test("A field with a comma, a double quote, a line feed or a carriage return is quoted, its quotes doubled", arguments: [
        ("a,b", #""a,b""#),
        (#"say "hi""#, #""say ""hi""""#),
        ("one\ntwo", "\"one\ntwo\""),
        ("one\r\ntwo", "\"one\r\ntwo\""),
        ("lone\rreturn", "\"lone\rreturn\""),
        ("plain text", "plain text"),
        ("'single'", "'single'"),
        ("", "")
    ])
    func escaping(field: String, expected: String) {
        let sut = ResultSet(columns: ["c"], rows: [[.text(field)]])

        let actual = sut.csv

        #expect(actual == "c\r\n\(expected)\r\n")
    }

    @Test("A real goes into CSV with every digit it needs to read back the same, not rounded as the cell shows it")
    func reals() {
        let sut = ResultSet(columns: ["total"], rows: [[.real(32.480000000000004)]])

        let actual = sut.csv

        #expect(actual == "total\r\n32.480000000000004\r\n")
    }

    @Test("Column names are escaped like values; no rows is the header alone; no columns is an empty header line")
    func edges() {
        let names = ResultSet(columns: [#"the "id""#, "a,b"], rows: [])
        let none = ResultSet(columns: [], rows: [])

        #expect(names.csv == #""the ""id""","a,b""# + "\r\n")
        #expect(none.csv == "\r\n")
    }
}
