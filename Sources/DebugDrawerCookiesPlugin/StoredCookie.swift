#if DEBUG
    import Foundation

    /// The cookie store a cookie is kept in.
    enum CookieStore: CaseIterable, Codable, Hashable, Sendable {
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
    struct StoredCookieID: Codable, Hashable, Sendable {
        let store: CookieStore
        let name: String
        let domain: String
        let path: String
    }

    // A value rather than the `HTTPCookie` it is read from: `HTTPCookie` isn't `Codable`, and the
    // snapshot that carries these must be. It keeps what the rows, the details and Copy show.

    /// A cookie, as the plugin shows it, and the store it is kept in.
    struct StoredCookie: Codable, Hashable, Identifiable, Sendable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let store: CookieStore
        /// Whether the cookie is sent only over secure connections.
        let isSecure: Bool
        /// Whether the cookie is kept from scripts.
        let isHTTPOnly: Bool
        /// When the cookie expires, or `nil` for one that lasts the session.
        let expiresDate: Date?

        var id: StoredCookieID {
            StoredCookieID(store: store, name: name, domain: domain, path: path)
        }
    }

    extension StoredCookie {
        /// What the list sorts by, most significant first.
        fileprivate var displayOrder: [String] {
            [domain, name, path, store.title]
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
                $0.name.localizedCaseInsensitiveContains(query) || $0.domain.localizedCaseInsensitiveContains(query)
            }
        }
    }
#endif
