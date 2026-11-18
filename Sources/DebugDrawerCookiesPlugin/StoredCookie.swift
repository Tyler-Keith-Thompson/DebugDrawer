#if DEBUG
    import Foundation

    /// The cookie store a cookie is kept in.
    enum CookieStore: CaseIterable, Hashable, Sendable {
        /// `HTTPCookieStorage.shared`, which URLSession's default configuration sends from.
        case urlSession
        /// `WKWebsiteDataStore.default().httpCookieStore`, which web views send from. Only
        /// platforms with WebKit have one.
        case webView

        /// The store's name as a row shows it.
        var title: String {
            switch self {
            case .urlSession: "URLSession"
            case .webView: "WKWebView"
            }
        }
    }

    /// What tells one stored cookie from another: a store keeps one cookie per name, domain and
    /// path, and two stores may each keep one with the same three.
    struct StoredCookieID: Hashable, Sendable {
        let store: CookieStore
        let name: String
        let domain: String
        let path: String
    }

    /// A cookie and the store it is kept in.
    struct StoredCookie: Identifiable {
        let cookie: HTTPCookie
        let store: CookieStore

        var id: StoredCookieID {
            StoredCookieID(store: store, name: cookie.name, domain: cookie.domain, path: cookie.path)
        }
    }

    extension StoredCookie {
        /// What the list sorts by, most significant first.
        fileprivate var displayOrder: [String] {
            [cookie.domain, cookie.name, cookie.path, store.title]
        }
    }

    extension [StoredCookie] {
        /// The cookies by domain, then name, then path, then store, so a list reads the same on
        /// every load.
        func sortedForDisplay() -> [StoredCookie] {
            sorted { $0.displayOrder.lexicographicallyPrecedes($1.displayOrder) }
        }

        /// The cookies whose name or domain contains `query`, ignoring case; all of them for an
        /// empty query.
        func matching(_ query: String) -> [StoredCookie] {
            guard !query.isEmpty else { return self }
            return filter {
                $0.cookie.name.localizedCaseInsensitiveContains(query) || $0.cookie.domain.localizedCaseInsensitiveContains(query)
            }
        }
    }
#endif
