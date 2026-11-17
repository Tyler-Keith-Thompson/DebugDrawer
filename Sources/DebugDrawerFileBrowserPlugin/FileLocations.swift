#if DEBUG
    import Foundation

    /// Where the app keeps its files: the folders the browser lists. The system's in production
    /// (`SystemFileLocations`), temporary folders a test makes in tests.
    protocol FileLocations: Sendable {
        /// The app's own folders, in the order the browser lists them: Documents, Library and tmp.
        var appFolders: [FileRoot] { get }
        /// The app's bundle.
        var bundle: URL { get }
        /// The shared container of an app group, or `nil` when the system gives the app none.
        func containerURL(forAppGroup identifier: String) -> URL?
    }
#endif
