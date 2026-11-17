#if DEBUG
    import Foundation
    import SQLite3

    /// Why a store couldn't be read, or a query was refused: one case per thing the drawer says.
    enum DatabaseError: Error, Hashable, Sendable {
        /// Another connection holds a lock the read needs, past the short busy timeout. Nothing
        /// retries it.
        case busy
        /// The authorizer refused the statement: it would write, attach, or change a setting.
        case refused(String)
        /// The statement passed the authorizer but SQLite says it would write.
        case writes
        /// SQL followed the first statement; only one runs at a time.
        case multipleStatements
        /// There was no statement to run, only whitespace or comments.
        case emptyQuery
        /// A WAL store whose `-shm` file, or the folder it would be made in, can't be written; a
        /// WAL read goes through it.
        case sharedMemoryNotWritable
        /// The file isn't a SQLite database.
        case notADatabase
        /// SQLite couldn't open the file.
        case cannotOpen(String)
        /// Any other SQLite failure, with its extended result code and message.
        case failed(code: Int32, message: String)

        /// The error a SQLite result code stands for.
        ///
        /// - Parameters:
        ///   - code: The extended result code.
        ///   - message: `sqlite3_errmsg`'s text.
        init(code: Int32, message: String) {
            switch code & 0xFF {
            case SQLITE_BUSY, SQLITE_LOCKED: self = .busy
            case SQLITE_AUTH: self = .refused(message)
            case SQLITE_NOTADB: self = .notADatabase
            case SQLITE_CANTOPEN: self = .cannotOpen(message)
            case SQLITE_READONLY where Self.sharedMemoryCodes.contains(code): self = .sharedMemoryNotWritable
            default: self = .failed(code: code, message: message)
            }
        }

        // SQLITE_READONLY_RECOVERY, _CANTLOCK, _CANTINIT and _DIRECTORY: a read-only connection
        // that can't open, lock, set up or create the -shm file of a WAL store. Spelled out, as
        // Swift doesn't import the header's macros for them.
        private static let sharedMemoryCodes: Set<Int32> = [1, 2, 5, 6].reduce(into: []) { codes, extended in
            codes.insert(SQLITE_READONLY | Int32(extended << 8))
        }
    }

    extension DatabaseError {
        /// What the drawer says went wrong, in a few words.
        var title: String {
            switch self {
            case .busy: "Store busy, try again"
            case .refused: "Refused: the browser only reads"
            case .writes: "Refused: the statement would write"
            case .multipleStatements: "Only one statement runs at a time"
            case .emptyQuery: "Nothing to run"
            case .sharedMemoryNotWritable: "Can't read this WAL store here"
            case .notADatabase: "Not a SQLite database"
            case .cannotOpen: "Can't open the store"
            case let .failed(code, _): "SQLite error \(code)"
            }
        }

        /// Why, and what to do about it.
        var explanation: String {
            switch self {
            case .busy:
                "Another connection holds a lock on it; the browser waited 250 ms and gave up rather than retry."
            case let .refused(message):
                "Only SELECT and a few schema pragmas run, so nothing can write, attach or change a setting. SQLite: \(message)."
            case .writes:
                "Only statements that read run."
            case .multipleStatements:
                "Remove what follows the first statement."
            case .emptyQuery:
                "Type a SELECT statement."
            case .sharedMemoryNotWritable:
                "A WAL store is read through its -shm file, which can't be written or created beside it."
            case .notADatabase:
                "The file doesn't start with SQLite's header; it may be encrypted or another format."
            case let .cannotOpen(message), let .failed(_, message):
                message
            }
        }
    }
#endif
