#if DEBUG
    /// What the plugin knows of the keychain.
    enum KeychainContents: Codable, Hashable, Sendable {
        /// Not read yet.
        case unread
        /// The items the app can read.
        case items([KeychainItem])
        /// The keychain refused to be read, as an unsigned Mac app's is.
        case unavailable(KeychainError)
    }
#endif
