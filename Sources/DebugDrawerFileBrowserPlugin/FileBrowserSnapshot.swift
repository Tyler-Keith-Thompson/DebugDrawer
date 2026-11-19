import Foundation

// Public because it is `FileBrowserModel`'s `Snapshot`, and opaque: its fields stay internal, so a
// reader outside the module carries it whole, encoded. It holds values read from the file system
// (paths, names, sizes in bytes, dates, whether each is a folder, a preview's text or a
// thumbnail's PNG); the view formats every size and date and draws the thumbnail.

#if DEBUG
    /// Everything the File Browser plugin shows, as a value: the list of roots, a folder or a
    /// file, the folder totals counted so far, and why the last change failed.
    ///
    /// ``FileBrowserModel`` makes it; the plugin's view draws it. It is `Codable`, so a transport
    /// can carry it.
    public struct FileBrowserSnapshot: Codable, Equatable, Sendable {
        /// What the browser shows.
        var screen: FileBrowserScreen
        /// The total size in bytes of each folder counted, by its path.
        var folderSizes: [String: Int64] = [:]
        /// Why the last import, rename or delete failed, until another place is shown.
        var failure: FileBrowserFailure?

        /// Where the browser is.
        var place: FileBrowserPlace {
            screen.place
        }
    }
#else
    /// Release builds read no files: this stand-in holds nothing.
    public struct FileBrowserSnapshot: Codable, Equatable, Sendable {}
#endif
