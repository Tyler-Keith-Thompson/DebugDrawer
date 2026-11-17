#if DEBUG
    /// The rows a statement returned, under its column names.
    struct ResultSet: Hashable, Sendable {
        /// The result's column names, in order.
        let columns: [String]
        /// Each row's values, one per column.
        let rows: [[SQLiteValue]]
        /// Whether the statement returned more rows than were read.
        let isTruncated: Bool

        init(columns: [String], rows: [[SQLiteValue]], isTruncated: Bool = false) {
            self.columns = columns
            self.rows = rows
            self.isTruncated = isTruncated
        }
    }
#endif
