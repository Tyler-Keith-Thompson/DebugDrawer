#if DEBUG
    import Combine
    import Foundation
    import os

    /// The stores the browser found, and the reads the drawer asks of them, each run on the
    /// store's own ``SQLiteStore``.
    ///
    /// Main-actor isolated, like the drawer that shows it; the file system and SQLite work runs
    /// off it.
    @MainActor
    final class DatabaseBrowserModel: ObservableObject {
        @Published private(set) var stores: StoresState = .loading

        private static let logger = Logger(subsystem: "DebugDrawerDatabaseBrowserPlugin", category: "DatabaseBrowserModel")
        private let discovery: StoreDiscovery
        private let busyTimeout: Duration
        /// One actor per store, made when the store is first read.
        private(set) var openStores: [DatabaseStore.ID: SQLiteStore] = [:]
        /// Counts reads, so one that finishes after a later one began is dropped.
        private var latestRead = 0
        /// The drawers the plugin is installed in; the first looks for stores, the last to remove
        /// it drops them.
        private var installations: Set<ObjectIdentifier> = []
        /// The look for stores the first install began, until it ends or the plugin is removed.
        private(set) var installRefresh: Task<Void, Never>?

        /// - Parameters:
        ///   - discovery: Where to look for stores.
        ///   - busyTimeout: How long a statement waits for another connection's lock.
        init(discovery: StoreDiscovery, busyTimeout: Duration = SQLiteStore.defaultBusyTimeout) {
            self.discovery = discovery
            self.busyTimeout = busyTimeout
        }

        /// The stores found, or none before the first refresh.
        var listings: [StoreListing] {
            if case let .loaded(listings) = stores { listings } else { [] }
        }

        /// Counts `drawer` as one the plugin is installed in; the first one looks for stores, so
        /// the header's count shows before the plugin is opened.
        func install(in drawer: ObjectIdentifier) {
            guard installations.insert(drawer).inserted, installations.count == 1 else { return }
            installRefresh = Task { await refresh() }
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, drops the stores found and their
        /// ``SQLiteStore``s, and any read still running.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            installRefresh?.cancel()
            installRefresh = nil
            // A read that finishes from now on is dropped.
            latestRead += 1
            openStores = [:]
            stores = .loading
        }

        /// Looks for stores again and reads each one's schema.
        func refresh() async {
            latestRead += 1
            let read = latestRead
            let discovery = discovery
            let found = await Task.detached(priority: .utility) { discovery.stores() }.value
            var listings: [StoreListing] = []
            for store in found {
                // A read overtaken, or dropped by uninstall, opens no more stores.
                guard read == latestRead, !Task.isCancelled else { return }
                do throws(DatabaseError) {
                    listings.append(StoreListing(store: store, schema: .success(try await sqliteStore(for: store).schema())))
                } catch {
                    Self.logger.notice("Couldn't read the schema of a store: \(error.title, privacy: .public)")
                    listings.append(StoreListing(store: store, schema: .failure(error.reading(store))))
                }
            }
            guard read == latestRead, !Task.isCancelled else {
                Self.logger.debug("Dropped a read that a later one overtook")
                return
            }
            Self.logger.debug("Found \(listings.count) stores")
            openStores = openStores.filter { id, _ in found.contains { $0.id == id } }
            stores = .loaded(listings)
        }

        /// Reads a page of a table's rows from `store`.
        func page(_ request: TablePageRequest, of store: DatabaseStore) async -> Loadable<TablePage> {
            do throws(DatabaseError) {
                return .loaded(try await sqliteStore(for: store).page(request))
            } catch {
                return .failed(error.reading(store))
            }
        }

        /// Runs one read-only statement on `store`.
        func run(_ sql: String, on store: DatabaseStore) async -> QueryState {
            do throws(DatabaseError) {
                return .finished(try await sqliteStore(for: store).run(sql))
            } catch {
                Self.logger.info("A query was refused or failed: \(error.title, privacy: .public)")
                return .failed(error.reading(store))
            }
        }

        private func sqliteStore(for store: DatabaseStore) -> SQLiteStore {
            if let open = openStores[store.id] {
                return open
            }
            let open = SQLiteStore(url: store.url, busyTimeout: busyTimeout)
            openStores[store.id] = open
            return open
        }
    }

    extension DatabaseError {
        /// The error as `store` explains it: SQLite says only that it can't open a WAL store whose
        /// `-shm` file can't be made, which is ``sharedMemoryNotWritable``.
        fileprivate func reading(_ store: DatabaseStore) -> DatabaseError {
            if case .cannotOpen = self, store.journalMode == .wal, !store.canWriteSharedMemory {
                return .sharedMemoryNotWritable
            }
            return self
        }
    }
#endif
