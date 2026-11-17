#if DEBUG
    import Foundation

    /// Where the app keeps its files: the folders the browser searches for stores. The system's
    /// in production (`SystemStoreLocations`), temporary folders a test makes in tests.
    protocol StoreLocations: Sendable {
        /// The app's Application Support folder, if it has one.
        var applicationSupport: URL? { get }
        /// The app's Documents folder, if it has one.
        var documents: URL? { get }
        /// The app groups the app's entitlements name (`com.apple.security.application-groups`).
        var appGroupIdentifiers: [String] { get }
        /// The shared container of an app group the app belongs to, or `nil` when the system gives
        /// it none.
        func containerURL(forAppGroup identifier: String) -> URL?
    }
#endif
