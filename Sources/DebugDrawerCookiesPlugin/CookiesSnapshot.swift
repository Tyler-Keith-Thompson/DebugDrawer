import Foundation

// Public because it is `CookiesModel`'s `Snapshot`, and opaque: its fields stay internal, so a
// reader outside the module carries it whole, encoded. It holds the cookies as values read from
// the stores and the filter; the count and which cookies the filter shows are worked out from
// them, and the view formats all of it.

#if DEBUG
    /// Everything the HTTP Cookies plugin shows, as a value: every store's cookies, once read, and
    /// the filter.
    ///
    /// ``CookiesModel`` makes it; the plugin's view draws it. It is `Codable`, so a transport can
    /// carry it.
    public struct CookiesSnapshot: Codable, Equatable, Sendable {
        /// The cookies read, or that none are yet.
        var contents = CookiesContents.unread
        /// What a cookie's name or domain must contain to be shown, ignoring case; empty shows
        /// every cookie.
        var filter = ""

        /// Every cookie, in every store.
        var allCookies: [StoredCookie] {
            guard case let .cookies(cookies) = contents else { return [] }
            return cookies
        }

        /// The cookies the filter lets through.
        var shownCookies: [StoredCookie] {
            allCookies.matching(filter)
        }

        /// How many cookies the filter shows, of how many there are.
        var count: CookieCount {
            CookieCount(shown: shownCookies.count, total: allCookies.count)
        }
    }
#else
    /// Release builds read no cookies: this stand-in holds nothing.
    public struct CookiesSnapshot: Codable, Equatable, Sendable {}
#endif
