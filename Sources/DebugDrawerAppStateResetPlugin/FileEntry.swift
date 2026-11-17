#if DEBUG
    import Foundation

    /// A file, folder or link the plugin will delete, as the list names it.
    struct FileEntry: Hashable, Sendable {
        /// Where it is.
        let url: URL
        /// Its path from the area it is in, starting with the area's name
        /// ("Documents/Drafts/notes.txt").
        let displayPath: String
        /// The bytes of the files it holds, its own for a file; a link counts as none, since
        /// deleting it leaves what it points to.
        let byteCount: Int64
    }

    /// A directory whose contents a category deletes, never the directory itself.
    struct FileArea: Hashable, Sendable {
        /// What the list calls it ("Documents", "group.com.example.shared").
        let name: String
        /// The directory.
        let directory: URL
    }
#endif
