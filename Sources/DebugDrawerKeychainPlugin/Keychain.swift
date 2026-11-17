#if DEBUG
    import Foundation
    import Security

    /// A keychain call that failed, with the `OSStatus` it returned.
    struct KeychainError: Error, Hashable, Sendable {
        let status: OSStatus

        /// Security's own words for the status, with its code ("A required entitlement isn't
        /// present. (-34018)").
        var message: String {
            let text = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "Keychain error"
            return "\(text) (\(status))"
        }
    }

    /// The keychain items the app can see: listed, read, added, updated and deleted.
    @MainActor
    protocol Keychain {
        /// Every item of every class the app can read, by its attributes, in class order.
        ///
        /// - Throws: `KeychainError` when the keychain can't be read at all.
        func items() throws(KeychainError) -> [KeychainItem]
        /// The password `item` holds; `nil` for an item that holds none, such as a key, whose
        /// data is never read.
        ///
        /// - Throws: `KeychainError` when the keychain refused.
        func value(of item: KeychainItem) throws(KeychainError) -> Data?
        /// Adds `password` as a new generic password.
        ///
        /// - Throws: `KeychainError`, with `errSecDuplicateItem` when one with its service and
        ///   account is already in the group.
        func add(_ password: GenericPassword) throws(KeychainError)
        /// Rewrites `item`, a generic password, as `password`, in the group it is in.
        ///
        /// - Throws: `KeychainError` when the keychain refused.
        func update(_ item: KeychainItem, to password: GenericPassword) throws(KeychainError)
        /// Deletes `item` alone; one already gone is no error.
        ///
        /// - Throws: `KeychainError` when the keychain refused.
        func delete(_ item: KeychainItem) throws(KeychainError)
    }
#endif
