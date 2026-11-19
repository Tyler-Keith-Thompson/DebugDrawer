#if DEBUG
    import DebugDrawer
    import Foundation

    /// The device's file system, through `FileManager` and `FileHandle`.
    ///
    /// Every call runs off the caller's actor: a folder's total walks its whole tree, and a read
    /// can take a while on a large file. Each is the drawer's own work, so Disk I/O leaves it out.
    struct _FileSystem: FileSystem {
        private static let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]

        @concurrent
        func item(at url: URL) async throws -> FileItem {
            try DebugDrawerActivity.$isDrawerWork.withValue(true) { try Self.item(at: url) }
        }

        @concurrent
        func contents(of url: URL) async throws -> [FileItem] {
            try DebugDrawerActivity.$isDrawerWork.withValue(true) {
                try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Self.keys).map(Self.item(at:))
            }
        }

        @concurrent
        func totalSize(of url: URL) async throws(CancellationError) -> Int64 {
            // Through a Result, as binding a task-local value doesn't keep the error's type.
            try DebugDrawerActivity.$isDrawerWork.withValue(true) {
                Result { () throws(CancellationError) in try Self.totalSize(of: url) }
            }.get()
        }

        @concurrent
        func read(_ url: URL, upTo limit: Int) async throws -> Data {
            try DebugDrawerActivity.$isDrawerWork.withValue(true) {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                return try handle.read(upToCount: limit) ?? Data()
            }
        }

        @concurrent
        func remove(_ url: URL) async throws {
            try DebugDrawerActivity.$isDrawerWork.withValue(true) { try FileManager.default.removeItem(at: url) }
        }

        @concurrent
        func move(_ url: URL, to destination: URL) async throws {
            try DebugDrawerActivity.$isDrawerWork.withValue(true) { try FileManager.default.moveItem(at: url, to: destination) }
        }

        @concurrent
        func copy(_ url: URL, to destination: URL) async throws {
            // A file the file importer picked is reachable only while its security scope is
            // open; for any other file this opens nothing.
            let isScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isScoped { url.stopAccessingSecurityScopedResource() }
            }
            try DebugDrawerActivity.$isDrawerWork.withValue(true) { try FileManager.default.copyItem(at: url, to: destination) }
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
