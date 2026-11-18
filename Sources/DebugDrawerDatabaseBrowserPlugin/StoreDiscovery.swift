#if DEBUG
    import DebugDrawer
    import Foundation

    /// Finds the app's SQLite stores: every file under Application Support, Documents, the app
    /// groups' containers and the folders the app added, at any depth, whose extension is
    /// `.sqlite`, `.sqlite3`, `.db` or `.store` (SwiftData's `default.store`) and which is empty
    /// or starts with SQLite's header. A store's `-wal`, `-shm` and `-journal` files are part of
    /// it, not stores of their own.
    struct StoreDiscovery: Sendable {
        /// The extensions a store's file may have.
        static let extensions: Set<String> = ["sqlite", "sqlite3", "db", "store"]

        let locations: any StoreLocations
        let additionalDirectories: [URL]

        /// A folder searched, and which of the app's folders it is.
        struct SearchRoot: Hashable, Sendable {
            let url: URL
            let location: StoreLocation
        }

        /// The folders searched, in the order their stores are listed: Application Support,
        /// Documents, each app group's container by identifier, then the added folders.
        var roots: [SearchRoot] {
            let system = [
                locations.applicationSupport.map { SearchRoot(url: $0, location: .applicationSupport) },
                locations.documents.map { SearchRoot(url: $0, location: .documents) }
            ].compactMap(\.self)
            let groups = locations.appGroupIdentifiers.sorted().compactMap { identifier in
                locations.containerURL(forAppGroup: identifier).map { SearchRoot(url: $0, location: .appGroup(identifier)) }
            }
            return system + groups + additionalDirectories.map { SearchRoot(url: $0, location: .additional) }
        }

        /// Every store under the roots, each listed once, under the first root it was found in.
        /// The search is the drawer's own work, which Disk I/O leaves out.
        ///
        /// - Complexity: O(*n*) in the number of files under the roots, reading the first 100
        ///   bytes of each whose extension fits.
        func stores() -> [DatabaseStore] {
            DebugDrawerActivity.$isDrawerWork.withValue(true) {
                var seen: Set<String> = []
                return roots.flatMap { root in
                    candidates(under: root.url)
                        .filter { seen.insert($0.resolvingSymlinksInPath().path(percentEncoded: false)).inserted }
                        .compactMap { store(at: $0, location: root.location) }
                }
            }
        }

        /// The files under `directory` whose names make them candidates, sorted by path.
        private func candidates(under directory: URL) -> [URL] {
            let keys: [URLResourceKey] = [.isRegularFileKey]
            guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return [] }
            return enumerator.compactMap { $0 as? URL }
                .filter { url in
                    (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true && url.isStoreCandidate
                }
                .sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
        }

        /// The store at `url`, or `nil` when the file isn't empty and doesn't start with SQLite's
        /// header.
        private func store(at url: URL, location: StoreLocation) -> DatabaseStore? {
            guard let header = Self.header(of: url) else { return nil }
            let path = url.path(percentEncoded: false)
            let journalMode: JournalMode
            if header.isEmpty {
                journalMode = .unknown
            } else if header.starts(with: Self.magic), header.count >= 20 {
                // Bytes 18 and 19: the write and read format versions, 2 in WAL mode.
                journalMode = header[header.startIndex + 18] == 2 && header[header.startIndex + 19] == 2 ? .wal : .rollback
            } else {
                return nil
            }
            return DatabaseStore(
                url: url,
                location: location,
                size: Self.size(ofFileAt: path) ?? 0,
                walSize: Self.size(ofFileAt: path + "-wal"),
                journalMode: journalMode,
                canWriteSharedMemory: journalMode != .wal || Self.canWriteSharedMemory(ofStoreAt: url)
            )
        }

        /// "SQLite format 3" and a NUL: the first 16 bytes of every SQLite database.
        private static let magic = Data("SQLite format 3\0".utf8)

        /// The file's first 100 bytes (SQLite's header), or `nil` when it can't be read.
        private static func header(of url: URL) -> Data? {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            return (try? handle.read(upToCount: 100)) ?? Data()
        }

        private static func size(ofFileAt path: String) -> Int64? {
            (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
        }

        /// Whether the `-shm` file can be written, or, where there is none yet, made beside the
        /// store.
        private static func canWriteSharedMemory(ofStoreAt url: URL) -> Bool {
            let sharedMemory = url.path(percentEncoded: false) + "-shm"
            return FileManager.default.fileExists(atPath: sharedMemory)
                ? FileManager.default.isWritableFile(atPath: sharedMemory)
                : FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path(percentEncoded: false))
        }
    }

    extension URL {
        /// Whether the file's extension is a store's and its name isn't a sidecar's
        /// (`-wal`, `-shm`, `-journal`).
        fileprivate var isStoreCandidate: Bool {
            let name = lastPathComponent
            let isSidecar = ["-wal", "-shm", "-journal"].contains { name.hasSuffix($0) }
            return !isSidecar && StoreDiscovery.extensions.contains(pathExtension.lowercased())
        }
    }
#endif
