#if DEBUG
    /// A value bound to a statement's `?`, so nothing typed or read is ever spliced into SQL.
    enum SQLiteParameter: Hashable, Sendable {
        case integer(Int64)
        case text(String)
    }
#endif
