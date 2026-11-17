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
    struct DatabaseBrowserViewTests {
        @Test("Before the first look the browser says it is looking; with no stores it says where it looked and offers Refresh")
        func emptyStates() throws {
            var refreshes = 0
            let loading = DatabaseBrowserView(
                stores: .loading, filter: .constant(""), selectedStore: .constant(nil), selectedTable: .constant(nil),
                search: .constant(""), page: .loading, sql: .constant(""), query: .idle, actions: DatabaseBrowserActions()
            )
            let none = DatabaseBrowserView(
                stores: .loaded([]), filter: .constant(""), selectedStore: .constant(nil), selectedTable: .constant(nil),
                search: .constant(""), page: .loading, sql: .constant(""), query: .idle,
                actions: DatabaseBrowserActions(refresh: { refreshes += 1 })
            )
            let expected = "No stores found. The browser looks in Application Support, Documents and the app groups' containers "
                + "for .sqlite, .sqlite3, .db and .store files."

            try none.inspect().find(button: "Refresh").tap()

            #expect(try loading.inspect().find(text: "Looking for stores…").string() == "Looking for stores…")
            #expect(try none.inspect().find(text: expected).string() == expected)
            #expect(refreshes == 1)
        }

        @Test("Each store shows its name, size, kind, journal and folder, and its path; tapping it selects it, tapping again clears it")
        func storeRows() throws {
            let store = DatabaseStore(
                url: URL(filePath: "/data/Application Support/Shop.sqlite"), location: .applicationSupport, size: 2048, walSize: 512,
                journalMode: .wal, canWriteSharedMemory: true
            )
            let listing = StoreListing(store: store, schema: .success(StoreSchema(kind: .sqlite, tables: [])))
            var selected: DatabaseStore.ID?
            let sut = DatabaseBrowserView(
                stores: .loaded([listing]), filter: .constant(""), selectedStore: Binding(get: { selected }, set: { selected = $0 }),
                selectedTable: .constant(nil), search: .constant(""), page: .loading, sql: .constant(""), query: .idle,
                actions: DatabaseBrowserActions()
            )

            let expectedSize = Int64(2048).formatted(.byteCount(style: .file))
            let expected = ["Shop.sqlite", expectedSize, "SQLite · WAL · Application Support", "/data/Application Support/Shop.sqlite"]

            let row = try sut.inspect().find(StoreRow.self)
            let texts = try row.findAll(ViewType.Text.self).prefix(4).map { try $0.string() }
            try row.find(ViewType.Button.self).tap()

            #expect(texts == expected)
            #expect(selected == store.id)

            try sut.inspect().find(StoreRow.self).find(ViewType.Button.self).tap()

            #expect(selected == nil)
        }

        @Test("The filter lists only the stores whose name, path, kind or table matches, and says when none does")
        func filter() throws {
            let shop = StoreListing(
                store: DatabaseStore(
                    url: URL(filePath: "/a/Shop.sqlite"), location: .documents, size: 0, walSize: nil, journalMode: .rollback,
                    canWriteSharedMemory: true
                ),
                schema: .success(StoreSchema(
                    kind: .sqlite, tables: [StoreTable(name: "orders", isView: false, columns: [], rowCount: 1, hasRowID: true)]
                ))
            )
            let notes = StoreListing(
                store: DatabaseStore(
                    url: URL(filePath: "/a/Notes.store"), location: .documents, size: 0, walSize: nil, journalMode: .wal,
                    canWriteSharedMemory: true
                ),
                schema: .success(StoreSchema(kind: .coreData(CoreDataMetadata()), tables: []))
            )
            func listed(_ query: String) throws -> [String] {
                let sut = DatabaseBrowserView(
                    stores: .loaded([shop, notes]), filter: .constant(query), selectedStore: .constant(nil), selectedTable: .constant(nil),
                    search: .constant(""), page: .loading, sql: .constant(""), query: .idle, actions: DatabaseBrowserActions()
                )
                return try sut.inspect().findAll(StoreRow.self).map { try $0.actualView().listing.store.name }
            }
            let none = DatabaseBrowserView(
                stores: .loaded([shop, notes]), filter: .constant(" invoices "), selectedStore: .constant(nil), selectedTable: .constant(nil),
                search: .constant(""), page: .loading, sql: .constant(""), query: .idle, actions: DatabaseBrowserActions()
            )

            #expect(try listed("ORDERS") == ["Shop.sqlite"])
            #expect(try listed("swiftdata") == ["Notes.store"])
            #expect(try listed("") == ["Shop.sqlite", "Notes.store"])
            #expect(try none.inspect().find(text: "No stores match “invoices”.").string() == "No stores match “invoices”.")
        }

        @Test("The selected store shows below the list: its path, facts as inspector rows, and its tables with row counts; tapping one selects it")
        func storeDetail() throws {
            let store = DatabaseStore(
                url: URL(filePath: "/data/Shop.sqlite"), location: .appGroup("group.com.example"), size: 4096, walSize: 1024,
                journalMode: .wal, canWriteSharedMemory: true
            )
            let tables = [
                StoreTable(name: "customers", isView: false, columns: [], rowCount: 120, hasRowID: true),
                StoreTable(name: "recent", isView: true, columns: [], rowCount: nil, hasRowID: false)
            ]
            let listing = StoreListing(store: store, schema: .success(StoreSchema(kind: .sqlite, tables: tables)))
            var selectedTable: StoreTable.ID?
            let sut = DatabaseBrowserView(
                stores: .loaded([listing]), filter: .constant(""), selectedStore: .constant(store.id),
                selectedTable: Binding(get: { selectedTable }, set: { selectedTable = $0 }), search: .constant(""), page: .loading,
                sql: .constant(""), query: .idle, actions: DatabaseBrowserActions()
            )
            let expectedLabels = ["Kind", "Folder", "Size", "Journal", "WAL file"]
            let expectedValues = [
                "SQLite", "App group group.com.example", Int64(4096).formatted(.byteCount(style: .file)), "WAL",
                Int64(1024).formatted(.byteCount(style: .file))
            ]

            let detail = try sut.inspect().find(StoreDetail.self)
            let rows = detail.findAll(DebugDrawerKeyValueRow.self)
            let path = try detail.find(DebugDrawerCodeText.self).actualView().text
            let counts = try detail.findAll(TableRow.self).map { try $0.actualView().table.rowCountText }
            try detail.find(TableRow.self).find(ViewType.Button.self).tap()

            #expect(try rows.map { try $0.actualView().label } == expectedLabels)
            #expect(try rows.map { try $0.actualView().value } == expectedValues)
            #expect(path == "/data/Shop.sqlite")
            #expect(counts == ["120 rows", "?"])
            #expect(try detail.find(text: "view").string() == "view")
            #expect(selectedTable == "customers")
            #expect(throws: (any Error).self) { try sut.inspect().find(ViewType.ScrollView.self).find(StoreDetail.self) }
        }

        @Test("A Core Data store lists its entities by name with the raw table below, then Core Data's own tables, and its model metadata")
        func coreDataDetail() throws {
            let store = DatabaseStore(
                url: URL(filePath: "/data/Notes.store"), location: .applicationSupport, size: 0, walSize: nil, journalMode: .wal,
                canWriteSharedMemory: true
            )
            let tables = [
                StoreTable(
                    name: "ZNOTE", isView: false, columns: [], rowCount: 12, hasRowID: true,
                    entity: CoreDataEntityTable(name: "Note", subentities: [])
                ),
                StoreTable(name: "Z_METADATA", isView: false, columns: [], rowCount: 1, hasRowID: true)
            ]
            let metadata = CoreDataMetadata(storeUUID: "6F1C-UUID", versionIdentifiers: ["v2"], versionHashesDigest: "aGFzaA==")
            let listing = StoreListing(store: store, schema: .success(StoreSchema(kind: .coreData(metadata), tables: tables)))
            let sut = StoreDetail(listing: listing, selectedTable: .constant(nil)) {}

            let names = try sut.inspect().findAll(TableRow.self).map { try $0.actualView().table.displayName }
            let values = try sut.inspect().findAll(DebugDrawerKeyValueRow.self).map { try $0.actualView().value }

            #expect(names == ["Note", "Z_METADATA"])
            #expect(try sut.inspect().find(text: "Entities").string() == "Entities")
            #expect(try sut.inspect().find(text: "Core Data's tables").string() == "Core Data's tables")
            #expect(try sut.inspect().find(text: "ZNOTE").string() == "ZNOTE")
            #expect(values.contains("Core Data / SwiftData") && values.contains("6F1C-UUID") && values.contains("v2") && values.contains("aGFzaA=="))
        }

        @Test("A store that can't be read says why as an issue row, and a WAL store with a read-only -shm warns")
        func storeIssues() throws {
            let broken = StoreListing(
                store: DatabaseStore(
                    url: URL(filePath: "/a/cache.db"), location: .documents, size: 100, walSize: nil, journalMode: .rollback,
                    canWriteSharedMemory: true
                ),
                schema: .failure(.notADatabase)
            )
            let readOnly = StoreListing(
                store: DatabaseStore(
                    url: URL(filePath: "/a/ro.sqlite"), location: .documents, size: 100, walSize: nil, journalMode: .wal,
                    canWriteSharedMemory: false
                ),
                schema: .success(StoreSchema(kind: .sqlite, tables: []))
            )

            let brokenDetail = StoreDetail(listing: broken, selectedTable: .constant(nil)) {}
            let readOnlyDetail = StoreDetail(listing: readOnly, selectedTable: .constant(nil)) {}

            let brokenRow = try brokenDetail.inspect().find(DebugDrawerIssueRow<Text, EmptyView>.self)
            let warning = try readOnlyDetail.inspect().find(DebugDrawerIssueRow<Text, EmptyView>.self)

            #expect(try brokenRow.actualView().title == "Not a SQLite database")
            #expect(try brokenRow.actualView().severity == .error)
            #expect(try warning.actualView().title == "Its -shm file is read-only")
            #expect(try warning.actualView().severity == .warning)
        }

        @Test("The selected table's rows show their range, the grid, and Previous and Next, disabled at the ends; Next asks for the next page")
        func tableRows() throws {
            let table = StoreTable(
                name: "customers", isView: false,
                columns: [StoreColumn(name: "id", declaredType: "INTEGER"), StoreColumn(name: "name", declaredType: "TEXT")],
                rowCount: 120, hasRowID: true
            )
            let page = TablePage(
                rows: ResultSet(columns: ["id", "name"], rows: [[.integer(1), .text("Ana")], [.integer(2), .null]]),
                pageIndex: 0, matchingCount: 120, searchedColumns: []
            )
            var shown: [Int] = []
            let sut = TableRowsSection(table: table, page: .loaded(page), search: .constant("")) { shown.append($0) }

            try sut.inspect().find(button: "Next").tap()

            #expect(try sut.inspect().find(text: "Rows 1–2 of 120").string() == "Rows 1–2 of 120")
            #expect(try sut.inspect().find(button: "Previous").isDisabled())
            #expect(try sut.inspect().find(button: "Next").isDisabled() == false)
            #expect(shown == [1])
            #expect(try sut.inspect().find(text: "Search looks in name, ignoring the case of ASCII letters.").string().hasPrefix("Search"))
            #expect(try sut.inspect().findAll(ValueCell.self).map { try $0.actualView().value } == [.integer(1), .text("Ana"), .integer(2), .null])
        }

        @Test("Typing in the search field changes the search; a table with no text columns disables it and says so")
        func search() throws {
            let text = StoreTable(name: "t", isView: false, columns: [StoreColumn(name: "name", declaredType: "TEXT")], rowCount: 0, hasRowID: true)
            let numbers = StoreTable(
                name: "n", isView: false, columns: [StoreColumn(name: "n", declaredType: "INTEGER")], rowCount: 0, hasRowID: true
            )
            var search = ""
            let sut = TableRowsSection(table: text, page: .loading, search: Binding(get: { search }, set: { search = $0 })) { _ in }
            let disabled = TableRowsSection(table: numbers, page: .loading, search: .constant("")) { _ in }

            try sut.inspect().find(ViewType.TextField.self).setInput("ana")

            #expect(search == "ana")
            #expect(try disabled.inspect().find(ViewType.TextField.self).isDisabled())
            #expect(try disabled.inspect().find(text: "The table has no text columns to search.").string().hasPrefix("The table"))
            #expect(try sut.inspect().find(text: "Reading…").string() == "Reading…")
        }

        @Test("A page that couldn't be read shows its error as an issue row, the busy one as Store busy, try again")
        func pageFailed() throws {
            let table = StoreTable(name: "t", isView: false, columns: [], rowCount: 0, hasRowID: true)
            let sut = TableRowsSection(table: table, page: .failed(.busy), search: .constant("")) { _ in }

            let row = try sut.inspect().find(DebugDrawerIssueRow<Text, EmptyView>.self).actualView()

            #expect(row.title == "Store busy, try again")
            #expect(row.severity == .error)
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Next") }
        }

        @Test("Run runs the query, and is disabled while the editor is blank or a query runs; typing changes the SQL")
        func queryEditor() throws {
            var runs = 0
            var sql = "SELECT 1"
            let sut = QuerySection(sql: Binding(get: { sql }, set: { sql = $0 }), state: .idle) { runs += 1 }
            let blank = QuerySection(sql: .constant("  \n"), state: .idle) {}
            let running = QuerySection(sql: .constant("SELECT 1"), state: .running) {}

            try sut.inspect().find(button: "Run").tap()
            try sut.inspect().find(ViewType.TextEditor.self).setInput("SELECT 2")

            #expect(runs == 1)
            #expect(sql == "SELECT 2")
            #expect(try blank.inspect().find(button: "Run").isDisabled())
            #expect(try running.inspect().find(button: "Run").isDisabled())
            #expect(try running.inspect().find(text: "Running…").string() == "Running…")
        }

        @Test("A refused query shows inline as an issue row; a finished one shows its grid and Copy Result as CSV")
        func queryResults() throws {
            let refused = QuerySection(sql: .constant("INSERT INTO t VALUES (1)"), state: .failed(.refused("not authorized"))) {}
            let result = ResultSet(columns: ["name", "total"], rows: [[.text("Ana"), .real(9.5)]])
            let finished = QuerySection(sql: .constant("SELECT name, total FROM orders JOIN customers"), state: .finished(result)) {}

            let issue = try refused.inspect().find(DebugDrawerIssueRow<Text, EmptyView>.self).actualView()
            let columns = try finished.inspect().find(ResultGrid.self).actualView().result.columns

            #expect(issue.title == "Refused: the browser only reads")
            let detail = try refused.inspect().find(ViewType.Text.self, where: { try $0.string().contains("not authorized") }).string()
            #expect(detail.hasSuffix("not authorized."))
            #expect(throws: (any Error).self) { try refused.inspect().find(button: "Copy Result as CSV") }
            #expect(columns == ["name", "total"])
            #expect(try finished.inspect().find(button: "Copy Result as CSV").isDisabled() == false)
        }
    }
#endif
