#if DEBUG
    /// A keychain call that failed, with the `OSStatus` it returned.
    struct KeychainError: Error, Codable, Hashable, Sendable {
        /// The `OSStatus` the call returned (`errSecMissingEntitlement`).
        let status: Int32
    }
#endif
