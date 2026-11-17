#if DEBUG
    /// What a store holds: its kind and its tables.
    struct StoreSchema: Hashable, Sendable {
        let kind: StoreKind
        /// Every table and view, entity tables first by entity name, then the rest by name.
        let tables: [StoreTable]

        /// A Core Data store's entity tables; empty for a plain SQLite store.
        var entityTables: [StoreTable] {
            tables.filter { $0.entity != nil }
        }

        /// The tables that hold no entity: every table of a plain SQLite store, and Core Data's
        /// own bookkeeping and join tables.
        var otherTables: [StoreTable] {
            tables.filter { $0.entity == nil }
        }
    }

    /// Whether a store is plain SQLite or Core Data's format, which SwiftData uses too.
    enum StoreKind: Hashable, Sendable {
        case sqlite
        case coreData(CoreDataMetadata)

        /// The kind as the store list names it.
        var title: String {
            switch self {
            case .sqlite: "SQLite"
            case .coreData: "Core Data / SwiftData"
            }
        }
    }

    /// What a Core Data store's `Z_METADATA` row says of it.
    struct CoreDataMetadata: Hashable, Sendable {
        /// The store's UUID (`NSStoreUUID`).
        var storeUUID: String?
        /// The model's version identifiers, as the app's model declares them; often empty.
        var versionIdentifiers: [String] = []
        /// A digest of the model's entity version hashes, which changes with the model.
        var versionHashesDigest: String?
    }
#endif
