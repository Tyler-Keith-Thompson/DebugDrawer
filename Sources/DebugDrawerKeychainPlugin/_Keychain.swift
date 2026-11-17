#if DEBUG
    import Foundation
    import Security

    /// The Security framework's keychain, scoped to the app.
    ///
    /// On iOS every app has a keychain of its own: a query that names no access group returns the
    /// items of every group its entitlements name (its app identifier, its keychain-access-groups
    /// and its app groups), and no other app's. On the Mac and in Mac Catalyst,
    /// `kSecUseDataProtectionKeychain` asks that same keychain, scoped the same way, rather than
    /// the login keychain, whose items belong to every app the user runs; a Mac app without the
    /// entitlements it needs gets `errSecMissingEntitlement`, which the plugin shows.
    ///
    /// Every item is reached by its persistent reference, so a read, an edit or a delete touches
    /// that item and no other with the same service or account. Certificates and keys are listed
    /// by their attributes alone: no query returns their data or a reference to them.
    struct _Keychain: Keychain {
        func items() throws(KeychainError) -> [KeychainItem] {
            var items: [KeychainItem] = []
            for itemClass in KeychainItemClass.allCases {
                var result: CFTypeRef?
                let status = SecItemCopyMatching(Self.listQuery(for: itemClass) as CFDictionary, &result)
                switch status {
                case errSecSuccess:
                    let found = (result as? [[String: Any]]) ?? []
                    items += found.compactMap { KeychainItem(itemClass: itemClass, result: $0) }
                case errSecItemNotFound:
                    continue
                default:
                    throw KeychainError(status: status)
                }
            }
            return items
        }

        func value(of item: KeychainItem) throws(KeychainError) -> Data? {
            guard item.itemClass.holdsPassword else { return nil }
            var result: CFTypeRef?
            let status = SecItemCopyMatching(Self.valueQuery(for: item) as CFDictionary, &result)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
            return result as? Data
        }

        func add(_ password: GenericPassword) throws(KeychainError) {
            let status = SecItemAdd(Self.addQuery(for: password) as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        }

        func update(_ item: KeychainItem, to password: GenericPassword) throws(KeychainError) {
            let status = SecItemUpdate(Self.itemQuery(for: item) as CFDictionary, Self.updatedAttributes(for: password) as CFDictionary)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        }

        func delete(_ item: KeychainItem) throws(KeychainError) {
            let status = SecItemDelete(Self.itemQuery(for: item) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
        }

        /// Every item of `itemClass`: its attributes and persistent reference, synchronized or
        /// not, in the data protection keychain. Never its data.
        static func listQuery(for itemClass: KeychainItemClass) -> [String: Any] {
            [
                kSecClass as String: itemClass.secClass,
                kSecMatchLimit as String: kSecMatchLimitAll,
                kSecReturnAttributes as String: true,
                kSecReturnPersistentRef as String: true,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                kSecUseDataProtectionKeychain as String: true
            ]
        }

        /// `item` alone, by its persistent reference: what an update or a delete matches.
        static func itemQuery(for item: KeychainItem) -> [String: Any] {
            [
                kSecClass as String: item.itemClass.secClass,
                kSecValuePersistentRef as String: item.persistentReference,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                kSecUseDataProtectionKeychain as String: true
            ]
        }

        /// The password of `item` alone.
        static func valueQuery(for item: KeychainItem) -> [String: Any] {
            itemQuery(for: item).merging([
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]) { _, new in new }
        }

        /// A new generic password, in `password`'s access group or the app's default one, kept on
        /// this device rather than synchronized.
        static func addQuery(for password: GenericPassword) -> [String: Any] {
            var query = updatedAttributes(for: password)
            query[kSecClass as String] = kSecClassGenericPassword
            query[kSecUseDataProtectionKeychain as String] = true
            if let group = password.accessGroup {
                query[kSecAttrAccessGroup as String] = group
            }
            if password.label.isEmpty {
                query.removeValue(forKey: kSecAttrLabel as String)
            }
            return query
        }

        /// What an edit writes: the service, account, label, password and accessibility.
        static func updatedAttributes(for password: GenericPassword) -> [String: Any] {
            [
                kSecAttrService as String: password.service,
                kSecAttrAccount as String: password.account,
                kSecAttrLabel as String: password.label,
                kSecValueData as String: Data(password.value.utf8),
                kSecAttrAccessible as String: password.accessibility.secValue
            ]
        }
    }
#endif
