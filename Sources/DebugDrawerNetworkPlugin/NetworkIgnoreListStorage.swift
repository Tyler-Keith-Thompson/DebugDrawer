#if DEBUG
    import Foundation

    /// Where the ignore list is kept between launches.
    protocol NetworkIgnoreListStorage: Sendable {
        /// The saved file's contents, or `nil` when nothing was ever saved.
        ///
        /// - Throws: When the file exists and can't be read.
        func readIgnoreList() throws -> Data?
        /// Replaces the saved file with `data`.
        func writeIgnoreList(_ data: Data) throws
    }

    /// The ignore list in `ignored.json`, beside the mock rules' `rules.json`.
    struct _NetworkIgnoreListStorage: NetworkIgnoreListStorage {
        let directory: URL

        private var file: URL {
            directory.appending(path: "ignored.json")
        }

        func readIgnoreList() throws -> Data? {
            guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return nil }
            return try Data(contentsOf: file)
        }

        func writeIgnoreList(_ data: Data) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        }
    }
#endif
