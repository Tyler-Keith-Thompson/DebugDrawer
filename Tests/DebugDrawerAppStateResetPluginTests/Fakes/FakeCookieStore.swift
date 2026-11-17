#if DEBUG
    @testable import DebugDrawerAppStateResetPlugin

    /// Cookie stores in memory, and every deletion asked for.
    @MainActor
    final class FakeCookieStore: CookieStore {
        var stored: [StoredCookie]
        private(set) var deleted: [StoredCookie] = []

        init(_ stored: [StoredCookie] = []) {
            self.stored = stored
        }

        func cookies() async -> [StoredCookie] {
            stored
        }

        func delete(_ cookies: [StoredCookie]) async {
            stored.removeAll { cookies.contains($0) }
            deleted += cookies
        }
    }
#endif
