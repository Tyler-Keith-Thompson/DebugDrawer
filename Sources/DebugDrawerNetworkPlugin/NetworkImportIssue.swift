#if DEBUG
    /// A HAR file that couldn't be imported, and why.
    struct NetworkImportIssue: Equatable, Codable, Sendable {
        let fileName: String
        let error: HTTPArchive.ReadError

        /// What the drawer says: the file's name and what went wrong.
        var message: String {
            "“\(fileName)” wasn't imported. \(error.message)"
        }
    }
#endif
