#if DEBUG
    import Foundation

    extension StoredCookie {
        /// `cookie`'s name, value, domain, path, flags and expiry, kept in `store`.
        init(cookie: HTTPCookie, store: CookieStore) {
            self.init(
                name: cookie.name, value: cookie.value, domain: cookie.domain, path: cookie.path, store: store,
                isSecure: cookie.isSecure, isHTTPOnly: cookie.isHTTPOnly, expiresDate: cookie.expiresDate
            )
        }
    }

    extension HTTPCookie {
        /// Whether this is the cookie `id` names, ignoring the store.
        func matches(_ id: StoredCookieID) -> Bool {
            name == id.name && domain == id.domain && path == id.path
        }
    }
#endif
