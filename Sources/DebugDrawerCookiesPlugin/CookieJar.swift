#if DEBUG
    import Foundation

    /// Every cookie store the app has, read and deleted from as one.
    @MainActor
    protocol CookieJar: Sendable {
        /// Every cookie in every store, each with the store it is in.
        func cookies() async -> [StoredCookie]
        /// Deletes `cookie` from the store it is in; one already gone is no error.
        func delete(_ cookie: StoredCookie) async
    }
#endif
