import Foundation

// Public because it is `FileBrowserModel`'s `Command`, and opaque: an enum's cases share its access
// level, and places and files are the plugin's own types, so the public type is a struct around
// the internal enum. Share, Copy Path, Copy Text and Reveal in Finder aren't commands: they hand
// the snapshot's values to the system's share sheet, clipboard or Finder, which is the view's.

#if DEBUG
    /// Something the File Browser plugin's view asks ``FileBrowserModel`` to do: go to a place,
    /// read it again, start or stop reading, or import, rename or delete a file. `Codable`, so a
    /// transport can carry it.
    public struct FileBrowserCommand: Codable, Sendable {
        /// What to do.
        enum Action: Codable, Equatable, Sendable {
            /// Shows the place, and reads it while the browser reads.
            case open(FileBrowserPlace)
            /// Shows the place one step up, and reads it while the browser reads.
            case back
            /// Reads the place shown again and counts its folders again.
            case refresh
            /// Starts reading: reads the place shown, then each place shown after, until
            /// ``stopReading``. Sent as a view of the browser appears; each view that sends it sends
            /// one ``stopReading`` too.
            case startReading
            /// Stops the reading one ``startReading`` began; once none is left, stops the read and
            /// the counting under way and reads nothing more.
            case stopReading
            /// Copies the file, as the file importer picked it, into the folder shown when sent,
            /// under a name of its own. Never into the bundle.
            case importFile(URL)
            /// Renames the file or folder, under the root shown when sent. Nothing in the bundle,
            /// and no root, is renamed.
            case rename(FileItem, to: String)
            /// Deletes the file or folder, under the root shown when sent. Nothing in the bundle,
            /// and no root, is deleted.
            case delete(FileItem)
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds read no files: this stand-in asks for nothing.
    public struct FileBrowserCommand: Codable, Sendable {}
#endif
