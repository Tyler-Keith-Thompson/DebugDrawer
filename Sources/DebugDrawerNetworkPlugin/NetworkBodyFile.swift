#if DEBUG
    import Foundation

    /// A temporary file holding a request's body, removed when the last reference to it goes.
    ///
    /// A class, so the file lives exactly as long as the protocol that forwards it, and every
    /// path out of a request (completion, cancellation, failure) removes it.
    final class NetworkBodyFile {
        /// The file's location, in the temporary directory.
        let url: URL

        /// Writes `contents` to a new temporary file.
        ///
        /// - Throws: `CocoaError(.fileWriteUnknown)` when the file can't be made.
        init(contents: Data) throws {
            let url = FileManager.default.temporaryDirectory.appending(path: "DebugDrawer-\(UUID().uuidString).body")
            guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: contents) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path(percentEncoded: false)])
            }
            self.url = url
        }

        /// A new stream of the file's bytes, from the start: for the forwarded request, and again
        /// whenever the session has to send the body over (a redirect, an authentication
        /// challenge).
        var stream: InputStream? {
            InputStream(url: url)
        }

        deinit {
            try? FileManager.default.removeItem(at: url)
        }
    }
#endif
