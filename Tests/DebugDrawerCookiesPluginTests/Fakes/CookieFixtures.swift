#if DEBUG
    @testable import DebugDrawerCookiesPlugin
    import Foundation

    /// Stored cookies for the model, views and snapshots.
    enum CookieFixtures {
        /// A cookie named `name` for `domain` at `path`, in `store`, with `value`. Every property
        /// `HTTPCookie(properties:)` requires is given, so it never returns `nil` and the force
        /// unwrap can't fire.
        static func stored(
            _ name: String, domain: String = "example.com", path: String = "/", value: String = "a1b2c3", in store: CookieStore = .urlSession
        ) -> StoredCookie {
            let cookie = HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: path])!
            return StoredCookie(cookie: cookie, store: store)
        }
    }
#endif
