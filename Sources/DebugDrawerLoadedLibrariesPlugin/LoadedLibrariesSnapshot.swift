import Foundation

// Public because it is `LoadedLibrariesModel`'s `Snapshot`, and opaque: its fields stay internal,
// so a reader outside the module carries it whole, encoded. It holds the libraries read, the
// filter and the category picked; which libraries they show is worked out from them, and the view
// formats all of it.

#if DEBUG
    /// Everything the Loaded Libraries plugin shows, as a value: the libraries read, the filter
    /// and the category picked.
    ///
    /// ``LoadedLibrariesModel`` makes it; the plugin's view draws it. It is `Codable`, so a
    /// transport can carry it.
    public struct LoadedLibrariesSnapshot: Codable, Equatable, Sendable {
        /// Every library read, sorted by name; empty until the images are read.
        var libraries: [LoadedLibrary] = []
        /// What a library's name or path must contain to be shown, ignoring case; empty shows
        /// every library.
        var filter = ""
        /// The one category shown, or `nil` for every category.
        var category: LibraryCategory?

        /// The libraries in the category picked whose name or path contains the filter.
        var shownLibraries: [LoadedLibrary] {
            var result = libraries
            if let category {
                result = result.filter { $0.category == category }
            }
            if !filter.isEmpty {
                let query = filter.lowercased()
                result = result.filter {
                    $0.name.lowercased().contains(query) || $0.path.lowercased().contains(query)
                }
            }
            return result
        }
    }
#else
    /// Release builds read no images: this stand-in holds nothing.
    public struct LoadedLibrariesSnapshot: Codable, Equatable, Sendable {}
#endif
