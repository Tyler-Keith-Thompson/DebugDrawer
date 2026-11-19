#if DEBUG
    @testable import DebugDrawerCookiesPlugin
    import Foundation

    /// Stored cookies for the model, views and snapshots.
    enum CookieFixtures {
        /// A session cookie named `name` for `domain` at `path`, in `store`, with `value`, neither
        /// secure nor HTTP-only.
        static func stored(
            _ name: String, domain: String = "example.com", path: String = "/", value: String = "a1b2c3", in store: CookieStore = .urlSession
        ) -> StoredCookie {
            StoredCookie(
                name: name, value: value, domain: domain, path: path, store: store, isSecure: false, isHTTPOnly: false, expiresDate: nil
            )
        }
    }
#endif
