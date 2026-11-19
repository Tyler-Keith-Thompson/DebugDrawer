#if DEBUG
    /// A change the keychain refused, as the plugin reports it.
    struct KeychainIssue: Codable, Hashable, Sendable {
        /// What was being done ("Couldn't save").
        let action: String
        let error: KeychainError
    }
#endif
