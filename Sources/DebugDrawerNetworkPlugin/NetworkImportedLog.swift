#if DEBUG
    import Foundation

    /// The requests in a HAR file read into the drawer, which the log shows in place of the
    /// captured ones, read-only, until it is cleared.
    struct NetworkImportedLog: Sendable {
        /// The file's name, `network.har`.
        let fileName: String
        /// The archive's requests, the newest first, as the log lists captured ones.
        let entries: [NetworkEntry]

        /// The requests in the archive `data`, read from the file named `fileName`.
        ///
        /// - Throws: What `HTTPArchive.read(_:)` throws for data that isn't a HAR 1.x archive.
        init(fileName: String, data: Data) throws(HTTPArchive.ReadError) {
            self.fileName = fileName
            entries = try HTTPArchive.read(data).log.entries.map(NetworkEntry.init).sorted { $0.timestamp > $1.timestamp }
        }

        /// The requests in the HAR file at `url`, which may be outside the app's sandbox, as the
        /// file importer hands it over.
        ///
        /// - Throws: `HTTPArchive.ReadError.unreadableFile` when the file can't be opened, and what
        ///   `HTTPArchive.read(_:)` throws when it isn't a HAR 1.x archive.
        init(contentsOf url: URL) throws(HTTPArchive.ReadError) {
            // A file from the importer on iOS is outside the sandbox until it is accessed.
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing { url.stopAccessingSecurityScopedResource() }
            }
            guard let data = try? Data(contentsOf: url) else { throw .unreadableFile }
            try self.init(fileName: url.lastPathComponent, data: data)
        }
    }
#endif
