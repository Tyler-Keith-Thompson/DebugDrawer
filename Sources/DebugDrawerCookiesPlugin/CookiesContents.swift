#if DEBUG
    /// What the plugin knows of the app's cookies.
    enum CookiesContents: Codable, Equatable, Sendable {
        /// Not read yet.
        case unread
        /// Every cookie in every store, sorted for display.
        case cookies([StoredCookie])
    }
#endif
