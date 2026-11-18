#if DEBUG
    @testable import DebugDrawerCookiesPlugin
    import Foundation

    /// Cookie stores in memory that behave as the real ones do for the calls the plugin makes: a
    /// cookie is deleted from its own store alone, and one already gone is no error. It records
    /// each delete, in order.
    @MainActor
    final class FakeCookieJar: CookieJar {
        private(set) var stored: [StoredCookie]
        /// The cookies deleted, in order.
        private(set) var deleted: [StoredCookie.ID] = []

        init(_ stored: [StoredCookie]) {
            self.stored = stored
        }

        func cookies() async -> [StoredCookie] {
            stored
        }

        func delete(_ cookie: StoredCookie) async {
            deleted.append(cookie.id)
            stored.removeAll { $0.id == cookie.id }
        }
    }
#endif
