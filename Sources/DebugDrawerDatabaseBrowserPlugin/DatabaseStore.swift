#if DEBUG
    import Foundation

    /// A database file the browser found, and what its header and the files beside it say.
    struct DatabaseStore: Identifiable, Hashable, Sendable {
        let url: URL
        let location: StoreLocation
        /// The database file's size in bytes.
        let size: Int64
        /// The `-wal` file's size in bytes, when there is one.
        let walSize: Int64?
        let journalMode: JournalMode
        /// For a WAL store, whether its `-shm` file can be written, or made where there is none;
        /// a WAL read needs it. Always true for a rollback-journal store.
        let canWriteSharedMemory: Bool

        var id: URL {
            url
        }

        /// The file's name.
        var name: String {
            url.lastPathComponent
        }

        /// The file's path.
        var path: String {
            url.path(percentEncoded: false)
        }
    }

    /// How a store keeps its transactions, from bytes 18 and 19 of its header.
    enum JournalMode: Hashable, Sendable {
        /// Write-ahead logging: readers read alongside a writer, through the `-wal` and `-shm`
        /// files.
        case wal
        /// A rollback journal (`DELETE`, `TRUNCATE`, `PERSIST` and the rest): a writer's commit
        /// waits for readers.
        case rollback
        /// An empty file, whose mode is set when it is first written.
        case unknown

        /// The mode as the store list shows it.
        var title: String {
            switch self {
            case .wal: "WAL"
            case .rollback: "Rollback journal"
            case .unknown: "Empty"
            }
        }
    }
#endif
