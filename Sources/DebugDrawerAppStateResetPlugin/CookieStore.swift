#if DEBUG
    import Foundation
    #if canImport(WebKit)
        import WebKit
    #endif

    /// A cookie the plugin will delete, from either store.
    struct StoredCookie: Hashable, Sendable {
        /// Which store holds it.
        enum Store: Hashable, Sendable {
            /// `HTTPCookieStorage.shared`, URLSession's.
            case http
            /// `WKWebsiteDataStore.default()`'s, the web views'.
            case web
        }

        let store: Store
        let name: String
        let domain: String
        let path: String
    }

    /// The app's cookies, URLSession's and its web views'.
    @MainActor
    protocol CookieStore {
        /// Every cookie in every store, sorted by domain, then name.
        func cookies() async -> [StoredCookie]
        /// Deletes `cookies`, waiting until each store has.
        func delete(_ cookies: [StoredCookie]) async
    }

    /// `HTTPCookieStorage.shared`, and `WKWebsiteDataStore.default()`'s cookie store where WebKit
    /// exists (not on tvOS).
    struct _CookieStore: CookieStore {
        func cookies() async -> [StoredCookie] {
            var cookies = (HTTPCookieStorage.shared.cookies ?? []).map { StoredCookie(.http, $0) }
            #if canImport(WebKit)
                cookies += await WKWebsiteDataStore.default().httpCookieStore.allCookies().map { StoredCookie(.web, $0) }
            #endif
            return cookies.sorted { ($0.domain, $0.name, $0.path) < ($1.domain, $1.name, $1.path) }
        }

        func delete(_ cookies: [StoredCookie]) async {
            let doomed = Set(cookies)
            for cookie in HTTPCookieStorage.shared.cookies ?? [] where doomed.contains(StoredCookie(.http, cookie)) {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
            #if canImport(WebKit)
                let store = WKWebsiteDataStore.default().httpCookieStore
                // Awaited one by one: WebKit writes each deletion through its network process,
                // and the app may quit as soon as this returns.
                for cookie in await store.allCookies() where doomed.contains(StoredCookie(.web, cookie)) {
                    await store.deleteCookie(cookie)
                }
            #endif
        }
    }

    extension StoredCookie {
        fileprivate init(_ store: Store, _ cookie: HTTPCookie) {
            self.init(store: store, name: cookie.name, domain: cookie.domain, path: cookie.path)
        }
    }
#endif
