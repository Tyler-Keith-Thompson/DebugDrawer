#if DEBUG
    import Foundation

    // The bytes travel with the command rather than a path to them, since the file the user picked
    // lives where the view runs, which needn't be the app's process; the name is chosen here, with
    // the bytes, so the editor can show the rule's body file before the model has stored it.

    /// A body file on its way into the mock storage: the name the rule will know it by, and its
    /// bytes.
    struct NetworkMockBodyUpload: Codable, Equatable, Sendable {
        /// The file's name in the storage: a new UUID, then the original's extension.
        let name: String
        /// The file's contents.
        let data: Data

        /// An upload of `data` under a new name.
        ///
        /// - Parameters:
        ///   - data: The file's contents.
        ///   - fileExtension: The extension to keep (without the dot), so the file keeps its type;
        ///     `nil` or empty for none.
        init(data: Data, fileExtension: String?) {
            name = UUID().uuidString + (fileExtension.map { $0.isEmpty ? "" : "." + $0 } ?? "")
            self.data = data
        }

        /// An upload of the file at `url`, keeping its extension; `nil` when it can't be read.
        ///
        /// - Parameter url: A file the user chose.
        init?(contentsOf url: URL) {
            // A file from the importer on iOS is outside the sandbox until it is accessed.
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing { url.stopAccessingSecurityScopedResource() }
            }
            guard let data = try? Data(contentsOf: url) else { return nil }
            self.init(data: data, fileExtension: url.pathExtension)
        }
    }
#endif
