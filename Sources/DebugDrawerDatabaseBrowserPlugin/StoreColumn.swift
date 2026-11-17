#if DEBUG
    /// A column of a table, as `PRAGMA table_info` describes it.
    struct StoreColumn: Hashable, Sendable {
        let name: String
        /// The type the table declares for it, as written (`VARCHAR`, `INTEGER`), or empty.
        let declaredType: String

        /// Whether search looks in it: a column of TEXT affinity (its declared type names
        /// `CHAR`, `CLOB` or `TEXT`, and not `INT`, by SQLite's affinity rules), or one with no
        /// declared type, which holds text as it was given.
        var isSearchable: Bool {
            let type = declaredType.uppercased()
            guard !type.contains("INT") else { return false }
            return type.isEmpty || ["CHAR", "CLOB", "TEXT"].contains { type.contains($0) }
        }
    }
#endif
