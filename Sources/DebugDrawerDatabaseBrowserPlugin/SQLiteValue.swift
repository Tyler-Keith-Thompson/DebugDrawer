#if DEBUG
    import Foundation

    /// One cell of a result, in one of SQLite's five storage classes. A blob keeps its size and
    /// only its first bytes, since a page of images would otherwise sit in memory to show a hex
    /// preview.
    enum SQLiteValue: Hashable, Sendable {
        case null
        case integer(Int64)
        case real(Double)
        case text(String)
        /// A blob: its size in bytes and its first bytes, up to the length the read asked for.
        case blob(size: Int, prefix: Data)

        /// How many of a blob's first bytes a cell reads, for its hex preview.
        static let previewLength = 16
    }
#endif
