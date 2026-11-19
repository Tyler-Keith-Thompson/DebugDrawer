#if DEBUG
    import Foundation

    /// Every cookie store the app has, read and deleted from as one.
    @MainActor
    protocol CookieJar: Sendable {
        /// Every cookie in every store, each with the store it is in.
        func cookies() async -> [StoredCookie]
        /// Deletes the cookie `id` names from the store it names; one already gone is no error.
        func delete(_ id: StoredCookieID) async
    }
#endif
