#if DEBUG
    import Foundation
    import SQLite3

    /// A read-only connection to one store, open only while one call on ``SQLiteStore`` runs and
    /// closed when released.
    ///
    /// Read-only four times over: opened `SQLITE_OPEN_READONLY`, `PRAGMA query_only` set, an
    /// authorizer that allows only reads (``SQLiteAuthorizer``), and `sqlite3_stmt_readonly`
    /// checked on every statement. It is not `immutable`, which would read a store the app is
    /// writing without its locks or WAL and could see stale or torn pages. A busy timeout keeps a
    /// writer's long transaction from hanging the drawer.
    ///
    /// Opened `SQLITE_OPEN_NOMUTEX`, so it is used from one thread at a time: the store's actor.
    final class SQLiteConnection {
        /// The SQLite connection.
        let handle: OpaquePointer

        /// Opens the store at `path` read-only.
        ///
        /// - Parameters:
        ///   - path: The database file.
        ///   - busyTimeout: How long a statement waits for another connection's lock before it
        ///     fails with ``DatabaseError/busy``.
        /// - Throws: ``DatabaseError`` when SQLite can't open it.
        init(readingAt path: String, busyTimeout: Duration) throws(DatabaseError) {
            var opened: OpaquePointer?
            let code = sqlite3_open_v2(path, &opened, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
            guard let opened else { throw .cannotOpen("SQLite couldn't allocate a connection.") }
            guard code == SQLITE_OK else {
                let error = Self.lastError(of: opened)
                sqlite3_close_v2(opened)
                throw error
            }
            sqlite3_extended_result_codes(opened, 1)
            sqlite3_busy_timeout(opened, Int32(busyTimeout / .milliseconds(1)))
            // Before the authorizer, which denies this pragma like every other setting.
            guard sqlite3_exec(opened, "PRAGMA query_only = ON", nil, nil, nil) == SQLITE_OK else {
                let error = Self.lastError(of: opened)
                sqlite3_close_v2(opened)
                throw error
            }
            SQLiteAuthorizer.install(on: opened)
            handle = opened
        }

        deinit {
            sqlite3_close_v2(handle)
        }

        /// Runs one read-only statement and reads its rows.
        ///
        /// Each statement runs in autocommit mode, so its read transaction ends when it is
        /// finalized here; nothing is held between calls.
        ///
        /// - Parameters:
        ///   - sql: One statement; trailing whitespace, semicolons and comments are allowed.
        ///   - parameters: Bound to its `?`s in order.
        ///   - maxRows: The most rows read; past it the result is truncated.
        ///   - blobPrefix: How many of each blob's first bytes are read.
        /// - Throws: ``DatabaseError``: ``DatabaseError/emptyQuery``,
        ///   ``DatabaseError/multipleStatements``, ``DatabaseError/refused(_:)`` or
        ///   ``DatabaseError/writes`` before it runs, or what SQLite reports while it runs.
        func query(
            _ sql: String,
            parameters: [SQLiteParameter] = [],
            maxRows: Int = .max,
            blobPrefix: Int = SQLiteValue.previewLength
        ) throws(DatabaseError) -> ResultSet {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(parameters, to: statement)
            let columnCount = sqlite3_column_count(statement)
            let columns = (0 ..< columnCount).map { sqlite3_column_name(statement, $0).map { String(cString: $0) } ?? "" }
            var rows: [[SQLiteValue]] = []
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { break }
                guard code == SQLITE_ROW else { throw Self.lastError(of: handle) }
                if rows.count == maxRows {
                    return ResultSet(columns: columns, rows: rows, isTruncated: true)
                }
                rows.append((0 ..< columnCount).map { value(at: $0, of: statement, blobPrefix: blobPrefix) })
            }
            return ResultSet(columns: columns, rows: rows)
        }

        /// Compiles `sql`'s one statement, refusing an empty one, a second statement after it,
        /// and one that would write.
        private func prepare(_ sql: String) throws(DatabaseError) -> OpaquePointer {
            let outcome: Result<OpaquePointer, DatabaseError> = sql.withCString { text in
                var statement: OpaquePointer?
                var tail: UnsafePointer<CChar>?
                guard sqlite3_prepare_v2(handle, text, -1, &statement, &tail) == SQLITE_OK else {
                    return .failure(Self.lastError(of: handle))
                }
                guard let statement else { return .failure(.emptyQuery) }
                // What follows may only be whitespace, semicolons and comments, which compile to
                // no statement; anything else, even a statement that fails to compile, is a
                // second one.
                if let tail, tail.pointee != 0 {
                    var next: OpaquePointer?
                    let code = sqlite3_prepare_v2(handle, tail, -1, &next, nil)
                    sqlite3_finalize(next)
                    guard code == SQLITE_OK, next == nil else {
                        sqlite3_finalize(statement)
                        return .failure(.multipleStatements)
                    }
                }
                guard sqlite3_stmt_readonly(statement) != 0 else {
                    sqlite3_finalize(statement)
                    return .failure(.writes)
                }
                return .success(statement)
            }
            return try outcome.get()
        }

        private func bind(_ parameters: [SQLiteParameter], to statement: OpaquePointer) throws(DatabaseError) {
            for (offset, parameter) in parameters.enumerated() {
                let index = Int32(offset + 1)
                let code = switch parameter {
                case let .integer(value): sqlite3_bind_int64(statement, index, value)
                case let .text(value): sqlite3_bind_text(statement, index, value, -1, Self.transient)
                }
                guard code == SQLITE_OK else { throw Self.lastError(of: handle) }
            }
        }

        private func value(at column: Int32, of statement: OpaquePointer, blobPrefix: Int) -> SQLiteValue {
            switch sqlite3_column_type(statement, column) {
            case SQLITE_INTEGER:
                return .integer(sqlite3_column_int64(statement, column))
            case SQLITE_FLOAT:
                return .real(sqlite3_column_double(statement, column))
            case SQLITE_TEXT:
                // The text first, then its length, as SQLite's docs order the calls.
                let text = sqlite3_column_text(statement, column)
                let count = Int(sqlite3_column_bytes(statement, column))
                guard let text else { return .text("") }
                // Initializing from the bytes repairs ill-formed UTF-8 with U+FFFD rather than
                // failing, so a column of bad text still shows.
                return .text(String(unsafeUninitializedCapacity: count) { buffer in
                    _ = buffer.initialize(fromContentsOf: UnsafeBufferPointer(start: text, count: count))
                    return count
                })
            case SQLITE_BLOB:
                let bytes = sqlite3_column_blob(statement, column)
                let count = Int(sqlite3_column_bytes(statement, column))
                return .blob(size: count, prefix: bytes.map { Data(bytes: $0, count: min(count, blobPrefix)) } ?? Data())
            default:
                return .null
            }
        }

        private static func lastError(of handle: OpaquePointer) -> DatabaseError {
            DatabaseError(code: sqlite3_extended_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
        }

        // SQLITE_TRANSIENT, which Swift doesn't import: SQLite copies the bound text before the
        // call returns, so Swift's temporary C string may go.
        private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
#endif
