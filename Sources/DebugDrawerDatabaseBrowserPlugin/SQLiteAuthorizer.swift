#if DEBUG
    import SQLite3

    /// What the browser's connections let a statement do, decided while SQLite compiles it
    /// (`sqlite3_set_authorizer`): read tables, select, call functions, and run the pragmas that
    /// describe a table. Everything else, writes, ATTACH, transactions and every other pragma
    /// (`journal_mode` among them) included, is denied, so the statement fails to compile and
    /// never runs.
    enum SQLiteAuthorizer {
        /// Pragmas that only describe a table or an index, whatever their argument.
        static let allowedPragmas: Set<String> = [
            "table_info", "table_xinfo", "index_list", "index_info", "index_xinfo", "foreign_key_list"
        ]

        /// The authorizer's answer for one action.
        ///
        /// - Parameters:
        ///   - action: The `SQLITE_*` action code.
        ///   - pragma: For `SQLITE_PRAGMA`, the pragma's name; ignored otherwise.
        /// - Returns: `SQLITE_OK` to allow it, `SQLITE_DENY` to fail the statement.
        static func decision(action: Int32, pragma: String?) -> Int32 {
            switch action {
            case SQLITE_READ, SQLITE_SELECT, SQLITE_FUNCTION:
                SQLITE_OK
            case SQLITE_PRAGMA where pragma.map { allowedPragmas.contains($0.lowercased()) } ?? false:
                SQLITE_OK
            default:
                SQLITE_DENY
            }
        }

        /// Installs the authorizer on `connection`.
        static func install(on connection: OpaquePointer) {
            // A closure that captures nothing, so it converts to the C function pointer SQLite
            // takes.
            sqlite3_set_authorizer(connection, { _, action, first, _, _, _ in
                SQLiteAuthorizer.decision(action: action, pragma: first.map { String(cString: $0) })
            }, nil)
        }
    }
#endif
