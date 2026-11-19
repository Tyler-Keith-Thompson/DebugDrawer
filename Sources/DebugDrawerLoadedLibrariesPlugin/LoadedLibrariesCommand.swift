import Foundation

// Public because it is `LoadedLibrariesModel`'s `Command`, and opaque: an enum's cases share its
// access level, and a category is the plugin's own type, so the public type is a struct around the
// internal enum. Copy isn't one: it reads the snapshot and writes the clipboard, which is the
// view's.

#if DEBUG
    /// Something the Loaded Libraries plugin's view asks ``LoadedLibrariesModel`` to do: read the
    /// loaded images again, change the filter or pick a category. `Codable`, so a transport can
    /// carry it.
    public struct LoadedLibrariesCommand: Codable, Sendable {
        /// What to do.
        enum Action: Codable, Sendable {
            /// Reads the loaded images again.
            case refresh
            /// Shows only the libraries whose name or path contains the text, ignoring case.
            case setFilter(String)
            /// Shows only the libraries in the category, or in every category for `nil`.
            case setCategory(LibraryCategory?)
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds read no images: this stand-in asks for nothing.
    public struct LoadedLibrariesCommand: Codable, Sendable {}
#endif
