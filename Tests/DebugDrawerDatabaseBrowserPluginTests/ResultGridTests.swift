// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerDatabaseBrowserPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ResultGridTests {
        @Test("The grid shows the column names, then each row's cells in order, in a sideways scroll view")
        func cells() throws {
            let result = ResultSet(columns: ["id", "name", "photo"], rows: [
                [.integer(1), .text("Ana"), .blob(size: 3, prefix: Data([1, 2, 3]))],
                [.integer(2), .null, .null]
            ])
            let sut = ResultGrid(result: result)
            let expectedCells = ["1", "Ana", "3 bytes · 01 02 03", "2", "NULL", "NULL"]

            let header = try sut.inspect().findAll(ViewType.Text.self).prefix(3).map { try $0.string() }
            let cells = try sut.inspect().findAll(ValueCell.self).map { try $0.find(ViewType.Text.self).string() }
            let axes = try sut.inspect().find(ViewType.ScrollView.self).axes()

            #expect(header == ["id", "name", "photo"])
            #expect(cells == expectedCells)
            #expect(axes == .horizontal)
            #expect(sut.notes.isEmpty)
        }

        @Test("No rows says so; a wide result draws at most 2,000 cells and says how many rows it shows; a truncated read says so")
        func notes() {
            let empty = ResultGrid(result: ResultSet(columns: ["id"], rows: []))
            let columns = (0 ..< 30).map { "c\($0)" }
            let rows: [[SQLiteValue]] = Array(repeating: Array(repeating: .integer(1), count: 30), count: 200)
            let wide = ResultGrid(result: ResultSet(columns: columns, rows: rows, isTruncated: true))
            let one = ResultGrid(result: ResultSet(columns: (0 ..< 3000).map { "c\($0)" }, rows: [Array(repeating: .null, count: 3000)]))

            #expect(empty.notes == ["No rows."])
            #expect(wide.shownRowCount == 66)
            #expect(wide.notes == [
                "Showing the first 66 of 200 rows: the grid draws at most 2,000 cells.", "Only the first 200 rows were read."
            ])
            #expect(one.shownRowCount == 1)
        }

        @Test("Tapping a cell selects it and shows its whole value, column and type below the grid; tapping it again hides them")
        func selectCell() async throws {
            let long = String(repeating: "lorem ipsum ", count: 10)
            let sut = ResultGrid(result: ResultSet(columns: ["id", "notes"], rows: [[.integer(7), .text(long)]]))

            try await ViewHosting.host(sut) {
                // The cell's tooltip and accessibility value hold the whole value too; the detail adds one more.
                try await sut.inspection.inspect { view in
                    #expect(throws: (any Error).self) { try view.find(text: "Row 1 · text") }
                    #expect(view.findAll(ViewType.Text.self).filter { (try? $0.string()) == long }.count == 3)
                    let cut = String(long.prefix(ValueCell.characterLimit)) + "…"
                    #expect(try view.findAll(ValueCell.self)[1].find(ViewType.Text.self).string() == cut)
                    try view.find(ViewType.Button.self, where: { try $0.accessibilityLabel().string().hasPrefix("notes, ") }).tap()
                }
                try await sut.inspection.inspect { view in
                    #expect(try view.find(text: "notes").string() == "notes")
                    #expect(try view.find(text: "Row 1 · text").string() == "Row 1 · text")
                    #expect(view.findAll(ViewType.Text.self).filter { (try? $0.string()) == long }.count == 4)
                    try view.find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "Close the value of notes" }).tap()
                }
                try await sut.inspection.inspect { view in
                    #expect(throws: (any Error).self) { try view.find(text: "Row 1 · text") }
                    #expect(view.findAll(ViewType.Text.self).filter { (try? $0.string()) == long }.count == 3)
                }
            }
        }

        @Test("Each storage class draws its own way: NULL tertiary (in italics, as the snapshots pin), numbers accent and trailing, text primary")
        func cellStyles() {
            let values: [SQLiteValue] = [.null, .integer(1), .real(1.5), .text("a"), .blob(size: 1, prefix: Data([0]))]
            let expectedStyles: [DebugDrawerForegroundStyle] = [.tertiary, .accent, .accent, .primary, .secondary]

            let styles = values.map { ValueCell(value: $0).foregroundStyle }
            let numbers = values.map { ValueCell(value: $0).isNumber }

            #expect(styles == expectedStyles)
            #expect(numbers == [false, true, true, false, false])
        }
    }
#endif
