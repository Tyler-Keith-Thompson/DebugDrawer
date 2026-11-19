#if DEBUG
    import Foundation
    import os

    /// The keys each of the app's bundles has in its tables, in any localization, by table: what
    /// tells the app's own strings from text that only passes through its bundle.
    ///
    /// SwiftUI looks some of its own strings up in the main bundle through the public lookup (an
    /// `.alert` title, say), the drawer's among them, with no default value; such a key is in no
    /// table of the app's. So a lookup counts as the app's when its key is in one of the bundle's
    /// tables or it passes a default value, as `NSLocalizedString(_:value:comment:)` does.
    ///
    /// A bundle's keys are read the first time one of its strings is looked up, under the lock, so
    /// they are read once.
    final class BundleTableKeys: Sendable {
        /// The keys, for the life of the app.
        static let shared = BundleTableKeys()

        private let keys = OSAllocatedUnfairLock<[String: [String: Set<String>]]>(initialState: [:])

        /// The keys of each table of the bundle at `path`, read now if they haven't been.
        func keys(ofBundleAt path: String) -> [String: Set<String>] {
            keys.withLock { keys in
                if let known = keys[path] {
                    return known
                }
                let read = Bundle(path: path).map { bundle in
                    BundleTableSource.read(bundle, isMain: false).tables.values.joined().reduce(into: [String: Set<String>]()) { keys, table in
                        keys[table.name, default: []].formUnion(table.entries.keys)
                    }
                } ?? [:]
                keys[path] = read
                return read
            }
        }

        /// Forgets every bundle's keys; the next lookup in a bundle reads them again.
        func removeAll() {
            keys.withLock { $0 = [:] }
        }
    }
#endif
