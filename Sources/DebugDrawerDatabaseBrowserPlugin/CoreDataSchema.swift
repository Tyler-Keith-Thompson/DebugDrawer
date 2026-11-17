#if DEBUG
    import Foundation

    // Core Data's store format, read through SQLite alone: no NSManagedObjectModel is loaded and
    // CoreData isn't imported. The app's own stack may have the store open, and the browser
    // doesn't own its model: a coordinator of its own could migrate the store, or hold locks the
    // app's stack then waits on. SwiftData writes the same format, so this covers it too.

    /// How the browser recognises a Core Data store and names its tables by entity.
    enum CoreDataSchema {
        /// A row of `Z_PRIMARYKEY`: an entity's number, name and parent's number (0 for none).
        struct Entity: Hashable, Sendable {
            let id: Int64
            let name: String
            let superID: Int64
        }

        /// Whether a store with these tables is in Core Data's format: it has `Z_METADATA` and
        /// `Z_PRIMARYKEY`.
        static func isCoreData(tableNames: Set<String>) -> Bool {
            tableNames.contains("Z_METADATA") && tableNames.contains("Z_PRIMARYKEY")
        }

        /// The entity each table holds, by table name. Core Data stores a root entity in the table
        /// `Z` + its name in capitals (`Order` in `ZORDER`), and its subentities in the same
        /// table, told apart by `Z_ENT`.
        static func entityTables(_ entities: [Entity]) -> [String: CoreDataEntityTable] {
            let byID = Dictionary(entities.map { ($0.id, $0) }) { first, _ in first }
            let grouped = Dictionary(grouping: entities) { root(of: $0, in: byID) }
            return grouped.reduce(into: [:]) { tables, group in
                let (root, members) = group
                let subentities = members.filter { $0.id != root.id }.map(\.name).sorted()
                tables["Z" + root.name.uppercased()] = CoreDataEntityTable(name: root.name, subentities: subentities)
            }
        }

        /// What `Z_METADATA`'s row says: the store's UUID, and from its property list the model's
        /// version identifiers and hashes digest.
        ///
        /// - Parameters:
        ///   - uuid: The row's `Z_UUID`.
        ///   - plist: The row's `Z_PLIST`, a property list of the store's metadata.
        static func metadata(uuid: String?, plist: Data?) -> CoreDataMetadata {
            let dictionary = plist.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any] ?? [:]
            let identifiers = (dictionary["NSStoreModelVersionIdentifiers"] as? [String] ?? []).filter { !$0.isEmpty }
            return CoreDataMetadata(
                storeUUID: uuid ?? dictionary["NSStoreUUID"] as? String,
                versionIdentifiers: identifiers,
                versionHashesDigest: dictionary["NSStoreModelVersionHashesDigest"] as? String
            )
        }

        /// The entity at the top of `entity`'s inheritance chain; a chain that loops or names a
        /// missing parent ends where it breaks.
        private static func root(of entity: Entity, in byID: [Int64: Entity]) -> Entity {
            var current = entity
            var seen: Set<Int64> = [entity.id]
            while let parent = byID[current.superID], seen.insert(parent.id).inserted {
                current = parent
            }
            return current
        }
    }
#endif
