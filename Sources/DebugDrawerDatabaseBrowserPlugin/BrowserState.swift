#if DEBUG
    /// A store the browser found, and its schema or why it couldn't be read.
    struct StoreListing: Identifiable, Hashable, Sendable {
        let store: DatabaseStore
        let schema: Result<StoreSchema, DatabaseError>

        var id: DatabaseStore.ID {
            store.id
        }
    }

    /// The stores, before and after they are first found.
    enum StoresState: Hashable, Sendable {
        case loading
        case loaded([StoreListing])
    }

    /// A read the drawer waits on: a page of rows.
    enum Loadable<Value: Hashable & Sendable>: Hashable, Sendable {
        case loading
        case loaded(Value)
        case failed(DatabaseError)
    }

    /// The query editor's result.
    enum QueryState: Hashable, Sendable {
        /// Nothing run yet.
        case idle
        case running
        case finished(ResultSet)
        case failed(DatabaseError)
    }
#endif
