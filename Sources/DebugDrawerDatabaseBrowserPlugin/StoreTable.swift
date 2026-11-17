#if DEBUG
    /// A table or view of a store, with its columns and how many rows it holds.
    struct StoreTable: Identifiable, Hashable, Sendable {
        /// The table's name in SQL.
        let name: String
        let isView: Bool
        let columns: [StoreColumn]
        /// How many rows it holds; `nil` when counting failed, as for a view over a table that
        /// no longer exists.
        let rowCount: Int?
        /// Whether its rows have a `rowid` to page them in a stable order: a table not declared
        /// `WITHOUT ROWID` with no column that hides the name.
        let hasRowID: Bool
        /// The Core Data entity whose rows it holds, for a Core Data store's entity table.
        var entity: CoreDataEntityTable?

        var id: String {
            name
        }

        /// The entity's name for an entity table, the table's own otherwise.
        var displayName: String {
            entity?.name ?? name
        }

        /// The columns search looks in.
        var searchableColumns: [String] {
            columns.filter(\.isSearchable).map(\.name)
        }
    }

    /// The Core Data entity a table stores: the root of an inheritance tree, whose subentities
    /// share its table.
    struct CoreDataEntityTable: Hashable, Sendable {
        let name: String
        /// The entities below it, stored in the same table, sorted.
        let subentities: [String]
    }
#endif
