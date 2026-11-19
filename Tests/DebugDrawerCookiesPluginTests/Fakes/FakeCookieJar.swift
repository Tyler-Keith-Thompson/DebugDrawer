#if DEBUG
    @testable import DebugDrawerCookiesPlugin
    import Foundation

    /// Cookie stores in memory that behave as the real ones do for the calls the plugin makes: a
    /// cookie is deleted from its own store alone, and one already gone is no error. It records
    /// each read and delete, in order.
    @MainActor
    final class FakeCookieJar: CookieJar {
        /// A call the plugin made.
        enum Call: Equatable {
            case read
            case delete(StoredCookie.ID)
        }

        private(set) var stored: [StoredCookie]
        /// The reads and deletes, in order.
        private(set) var calls: [Call] = []

        /// The cookies deleted, in order.
        var deleted: [StoredCookie.ID] {
            calls.compactMap { call in
                guard case let .delete(id) = call else { return nil }
                return id
            }
        }

        init(_ stored: [StoredCookie]) {
            self.stored = stored
        }

        /// Sets `cookie` as the app would, replacing one with the same identity.
        func set(_ cookie: StoredCookie) {
            stored.removeAll { $0.id == cookie.id }
            stored.append(cookie)
        }

        func cookies() async -> [StoredCookie] {
            calls.append(.read)
            return stored
        }

        func delete(_ id: StoredCookie.ID) async {
            calls.append(.delete(id))
            stored.removeAll { $0.id == id }
        }
    }
#endif
