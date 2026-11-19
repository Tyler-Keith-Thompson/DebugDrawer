#if DEBUG
    import Foundation

    /// The keychain items the app can see: listed, read, added, updated and deleted. The Security
    /// framework's `SecItem` calls are `_Keychain`; tests pass a fake.
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
