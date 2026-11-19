#if DEBUG
    import Foundation

    /// The file system the browser reads and changes: `_FileSystem` in production, a fake in
    /// memory in tests.
    protocol FileSystem: Sendable {
        /// The file or folder at `url`: its size, its dates and whether it is a folder.
        func item(at url: URL) async throws -> FileItem

        /// What the folder at `url` holds, in no particular order.
        func contents(of url: URL) async throws -> [FileItem]

        /// The total size in bytes of the files in the folder at `url`, at any depth; links are
        /// counted as links, not followed. What can't be read counts as nothing.
        ///
        /// - Throws: `CancellationError` once the task is cancelled, which it checks file by file.
        func totalSize(of url: URL) async throws(CancellationError) -> Int64

        /// The first `limit` bytes of the file at `url`, or all of it when it is shorter.
        func read(_ url: URL, upTo limit: Int) async throws -> Data

        /// Deletes the file or folder at `url`, and a folder's contents with it.
        func remove(_ url: URL) async throws

        /// Moves the file or folder at `url` to `destination`, which must not exist.
        func move(_ url: URL, to destination: URL) async throws

        /// Copies the file or folder at `url`, which may be one the file importer picked from
        /// outside the app, to `destination`, which must not exist.
        func copy(_ url: URL, to destination: URL) async throws
    }
#endif
