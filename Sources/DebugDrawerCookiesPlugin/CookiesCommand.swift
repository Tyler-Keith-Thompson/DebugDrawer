import Foundation

// Public because it is `CookiesModel`'s `Command`, and opaque: an enum's cases share its access
// level, and a cookie's identity is the plugin's own type, so the public type is a struct around
// the internal enum. Copy isn't one: it reads the snapshot and writes the clipboard, which is the
// view's.

#if DEBUG
    /// Something the HTTP Cookies plugin's view asks ``CookiesModel`` to do: read the stores
    /// again, change the filter, delete one cookie or every cookie the filter shows. `Codable`, so
    /// a transport can carry it.
    public struct CookiesCommand: Codable, Sendable {
        /// What to do.
        enum Action: Codable, Sendable {
            /// Reads every store again.
            case reload
            /// Shows only the cookies whose name or domain contains the text, ignoring case.
            case setFilter(String)
            /// Deletes the cookie from the store it is in, then reads the stores again.
            case delete(StoredCookieID)
            /// Deletes the cookies the filter shows as the command is performed, each from its own
            /// store and no others, then reads the stores again.
            case deleteShown
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds read no cookies: this stand-in asks for nothing.
    public struct CookiesCommand: Codable, Sendable {}
#endif
