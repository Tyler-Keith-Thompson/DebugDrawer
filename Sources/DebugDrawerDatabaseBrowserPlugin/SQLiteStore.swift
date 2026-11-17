#if DEBUG
    import Foundation

    // An actor rather than a Mutex: a call can block for as long as a query runs or the busy
    // timeout waits, and its callers are the drawer's views, which await it, where a Mutex would
    // hold their thread (the main thread) that long. It runs on a serial queue of its own rather
    // than the shared cooperative pool, since SQLite's calls block a thread while they run.

    /// One store, read off the main actor: its schema, a page of a table, or a query. Each call
    /// opens a read-only ``SQLiteConnection``, runs, and closes it before returning, so no read
    /// transaction stays open while the drawer sits idle; one would stop the app's WAL from being
    /// checkpointed, and the WAL would grow.
    actor SQLiteStore {
        /// How long a statement waits for another connection's lock before it fails with
        /// ``DatabaseError/busy``: short, so a writer's long transaction doesn't hang the drawer.
        static let defaultBusyTimeout = Duration.milliseconds(250)
        /// The most rows a query reads; past it the result says it was truncated.
        static let queryRowLimit = 200

        let url: URL
        private let busyTimeout: Duration
        private let queue: DispatchSerialQueue

        /// - Parameters:
        ///   - url: The database file.
        ///   - busyTimeout: How long a statement waits for another connection's lock.
        init(url: URL, busyTimeout: Duration = defaultBusyTimeout) {
            self.url = url
            self.busyTimeout = busyTimeout
            queue = DispatchSerialQueue(label: "DebugDrawerDatabaseBrowserPlugin.SQLiteStore")
        }

        nonisolated var unownedExecutor: UnownedSerialExecutor {
            queue.asUnownedSerialExecutor()
        }

        /// The store's kind and its tables and views with their columns and row counts.
        ///
        /// - Throws: ``DatabaseError`` when the store can't be opened or read.
        func schema() throws(DatabaseError) -> StoreSchema {
            try withConnection { connection throws(DatabaseError) in
                let entries = try connection.query(
                    "SELECT name, type, sql FROM sqlite_schema WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'"
                )
                var tables: [StoreTable] = []
                for row in entries.rows {
                    guard case let .text(name) = row[0] else { continue }
                    tables.append(try table(named: name, type: row[1], sql: row[2], in: connection))
                }
                let names = Set(tables.map(\.name))
                guard CoreDataSchema.isCoreData(tableNames: names) else {
                    return StoreSchema(kind: .sqlite, tables: tables.sorted { $0.name < $1.name })
                }
                return try coreDataSchema(of: tables, in: connection)
            }
        }

        /// A page of a table's rows, among those the search matches.
        ///
        /// - Throws: ``DatabaseError`` when the store can't be opened or read.
        func page(_ request: TablePageRequest) throws(DatabaseError) -> TablePage {
            try withConnection { connection throws(DatabaseError) in
                let count = try connection.query(request.countSQL, parameters: request.searchParameters)
                guard case let .integer(matching) = count.rows.first?.first else {
                    return TablePage(rows: ResultSet(columns: [], rows: []), pageIndex: 0, matchingCount: 0, searchedColumns: [])
                }
                let pageIndex = request.clampedPageIndex(matching: Int(matching))
                let limits: [SQLiteParameter] = [
                    .integer(Int64(TablePageRequest.pageSize)), .integer(Int64(pageIndex * TablePageRequest.pageSize))
                ]
                let rows = try connection.query(request.pageSQL, parameters: request.searchParameters + limits)
                return TablePage(rows: rows, pageIndex: pageIndex, matchingCount: Int(matching), searchedColumns: request.searchedColumns)
            }
        }

        /// Runs one read-only statement typed into the drawer.
        ///
        /// - Returns: Its first ``queryRowLimit`` rows.
        /// - Throws: ``DatabaseError``: refusals before it runs, or what SQLite reports.
        func run(_ sql: String) throws(DatabaseError) -> ResultSet {
            try withConnection { connection throws(DatabaseError) in
                try connection.query(sql, maxRows: Self.queryRowLimit)
            }
        }

        /// Opens a connection for `body` alone; it closes when `body` returns.
        private func withConnection<Value>(_ body: (SQLiteConnection) throws(DatabaseError) -> Value) throws(DatabaseError) -> Value {
            let connection = try SQLiteConnection(readingAt: url.path(percentEncoded: false), busyTimeout: busyTimeout)
            return try body(connection)
        }

        private func table(
            named name: String, type: SQLiteValue, sql: SQLiteValue, in connection: SQLiteConnection
        ) throws(DatabaseError) -> StoreTable {
            let info = try connection.query("PRAGMA table_info(\(name.quotedSQLIdentifier))")
            let columns = info.rows.map { row in
                StoreColumn(name: row[1].textValue ?? "", declaredType: row[2].textValue ?? "")
            }
            let rowCount: Int?
            do {
                let count = try connection.query("SELECT count(*) FROM \(name.quotedSQLIdentifier)")
                rowCount = count.rows.first?.first?.integerValue.map(Int.init)
            } catch .busy {
                throw .busy
            } catch {
                // A view over a table that's gone, or a virtual table whose module isn't loaded:
                // listed with no count.
                rowCount = nil
            }
            let isView = type == .text("view")
            let withoutRowID = sql.textValue?.range(of: "WITHOUT ROWID", options: .caseInsensitive) != nil
            let hidesRowID = columns.contains { ["rowid", "_rowid_", "oid"].contains($0.name.lowercased()) }
            return StoreTable(name: name, isView: isView, columns: columns, rowCount: rowCount, hasRowID: !isView && !withoutRowID && !hidesRowID)
        }

        private func coreDataSchema(of tables: [StoreTable], in connection: SQLiteConnection) throws(DatabaseError) -> StoreSchema {
            let keys = try connection.query("SELECT Z_ENT, Z_NAME, Z_SUPER FROM Z_PRIMARYKEY")
            let entities = keys.rows.compactMap { row -> CoreDataSchema.Entity? in
                guard let id = row[0].integerValue, let name = row[1].textValue else { return nil }
                return CoreDataSchema.Entity(id: id, name: name, superID: row[2].integerValue ?? 0)
            }
            let metadata = try connection.query("SELECT Z_UUID, Z_PLIST FROM Z_METADATA LIMIT 1", blobPrefix: .max)
            let row = metadata.rows.first
            let plist: Data? = if case let .blob(_, data) = row?[1] { data } else { nil }
            let entityTables = CoreDataSchema.entityTables(entities)
            let named = tables.map { table in
                var table = table
                table.entity = entityTables[table.name]
                return table
            }
            let ordered = named.filter { $0.entity != nil }.sorted { $0.displayName < $1.displayName }
                + named.filter { $0.entity == nil }.sorted { $0.name < $1.name }
            return StoreSchema(kind: .coreData(CoreDataSchema.metadata(uuid: row?[0].textValue, plist: plist)), tables: ordered)
        }
    }

    extension SQLiteValue {
        /// The text, for a text value.
        fileprivate var textValue: String? {
            if case let .text(value) = self { value } else { nil }
        }

        /// The integer, for an integer value.
        fileprivate var integerValue: Int64? {
            if case let .integer(value) = self { value } else { nil }
        }
    }
#endif
