#if DEBUG
    import Foundation

    /// The device's file system, through `FileManager` and `FileHandle`.
    ///
    /// Every call runs off the caller's actor: a folder's total walks its whole tree, and a read
    /// can take a while on a large file.
    struct LocalFileSystem: FileSystem {
        private static let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]

        @concurrent
        func item(at url: URL) async throws -> FileItem {
            try Self.item(at: url)
        }

        @concurrent
        func contents(of url: URL) async throws -> [FileItem] {
            try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Self.keys)
                .map(Self.item(at:))
                .sorted { lhs, rhs in
                    lhs.isDirectory != rhs.isDirectory ? lhs.isDirectory : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
        }

        @concurrent
        func totalSize(of url: URL) async throws(CancellationError) -> Int64 {
            try Self.totalSize(of: url)
        }

        @concurrent
        func read(_ url: URL, upTo limit: Int) async throws -> Data {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            return try handle.read(upToCount: limit) ?? Data()
        }

        @concurrent
        func remove(_ url: URL) async throws {
            try FileManager.default.removeItem(at: url)
        }

        @concurrent
        func move(_ url: URL, to destination: URL) async throws {
            try FileManager.default.moveItem(at: url, to: destination)
        }

        @concurrent
        func copy(_ url: URL, to destination: URL) async throws {
            try FileManager.default.copyItem(at: url, to: destination)
        }

        // Synchronous, as a directory enumerator can't be iterated in an async context.
        private static func totalSize(of url: URL) throws(CancellationError) -> Int64 {
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
            // No options: hidden files count too, and links aren't followed out of the folder.
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: []) { _, _ in true }
            guard let enumerator else { return 0 }
            var total: Int64 = 0
            for case let file as URL in enumerator {
                if Task.isCancelled { throw CancellationError() }
                guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                total += Int64(values.fileSize ?? 0)
            }
            return total
        }

        private static func item(at url: URL) throws -> FileItem {
            let values = try url.resourceValues(forKeys: Set(keys))
            let isDirectory = values.isDirectory ?? false
            return FileItem(
                url: url,
                isDirectory: isDirectory,
                size: isDirectory ? 0 : Int64(values.fileSize ?? 0),
                modified: values.contentModificationDate,
                created: values.creationDate
            )
        }
    }
#endif
