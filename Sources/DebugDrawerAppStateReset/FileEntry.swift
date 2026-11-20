import Foundation

/// A file, folder or link the plugin will delete, as the list names it.
package struct FileEntry: Hashable, Sendable {
    /// Where it is.
    package let url: URL
    /// Its path from the area it is in, starting with the area's name
    /// ("Documents/Drafts/notes.txt").
    package let displayPath: String
    /// The bytes of the files it holds, its own for a file; a link counts as none, since
    /// deleting it leaves what it points to.
    package let byteCount: Int64
}

/// A directory whose contents a category deletes, never the directory itself.
package struct FileArea: Hashable, Sendable {
    /// What the list calls it ("Documents", "group.com.example.shared").
    package let name: String
    /// The directory.
    package let directory: URL

    package init(name: String, directory: URL) {
        self.name = name
        self.directory = directory
    }
}
