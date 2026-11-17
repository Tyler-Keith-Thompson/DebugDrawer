#if DEBUG
    import Foundation
    import Security

    /// A keychain item the app can read, as the plugin lists it before deleting it.
    struct KeychainItem: Hashable, Sendable {
        /// Which of the keychain's classes it is.
        let itemClass: KeychainItemClass
        /// The service of a generic password, or the server of an internet password.
        let service: String?
        /// The account of a password.
        let account: String?
        /// The label of a certificate, key or identity, which has no service or account.
        let label: String?
        /// The keychain's handle on this one item, which deletes it and nothing else.
        let persistentReference: Data

        /// What the list calls it: "service · account" for a password, its label otherwise.
        var name: String {
            let parts = [service, account].compactMap { $0?.isEmpty == false ? $0 : nil }
            if !parts.isEmpty { return parts.joined(separator: " · ") }
            return label.flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed \(itemClass.title.lowercased())"
        }
    }

    /// The keychain's item classes, each queried and deleted on its own.
    enum KeychainItemClass: CaseIterable, Hashable, Sendable {
        case genericPassword
        case internetPassword
        case certificate
        case key
        /// A certificate with its private key. Deleting it deletes both, which are listed as items
        /// of their own too.
        case identity

        var secClass: CFString {
            switch self {
            case .genericPassword: kSecClassGenericPassword
            case .internetPassword: kSecClassInternetPassword
            case .certificate: kSecClassCertificate
            case .key: kSecClassKey
            case .identity: kSecClassIdentity
            }
        }

        var title: String {
            switch self {
            case .genericPassword: "Password"
            case .internetPassword: "Internet password"
            case .certificate: "Certificate"
            case .key: "Key"
            case .identity: "Identity"
            }
        }
    }

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

    /// The keychain items the app can see, and their deletion.
    @MainActor
    protocol Keychain {
        /// Every item of every class the app can read, in class order.
        ///
        /// - Throws: `KeychainError` when the keychain can't be read at all.
        func items() throws(KeychainError) -> [KeychainItem]
        /// Deletes `item`; one already gone is no error.
        ///
        /// - Throws: `KeychainError` when the keychain refused.
        func delete(_ item: KeychainItem) throws(KeychainError)
    }

    /// The Security framework's keychain, scoped to the app.
    ///
    /// On iOS, tvOS and visionOS every app has a keychain of its own: a query with no access
    /// group returns only the items of the groups its entitlements name (its app identifier, its
    /// keychain-access-groups and its app groups), so another app's items can't be seen. On the
    /// Mac and in Mac Catalyst, `kSecUseDataProtectionKeychain` asks the same keychain with the
    /// same scoping, rather than the login keychain, whose items belong to every app the user runs
    /// and are only guarded by prompts; a Mac app without the entitlements it needs gets
    /// `errSecMissingEntitlement`, which the plugin shows, and touches nothing.
    struct _Keychain: Keychain {
        func items() throws(KeychainError) -> [KeychainItem] {
            var items: [KeychainItem] = []
            for itemClass in KeychainItemClass.allCases {
                var result: CFTypeRef?
                let status = SecItemCopyMatching(Self.listQuery(for: itemClass) as CFDictionary, &result)
                switch status {
                case errSecSuccess:
                    let found = (result as? [[String: Any]]) ?? []
                    items += found.compactMap { KeychainItem(itemClass: itemClass, attributes: $0) }
                case errSecItemNotFound:
                    continue
                default:
                    throw KeychainError(status: status)
                }
            }
            return items
        }

        func delete(_ item: KeychainItem) throws(KeychainError) {
            let status = SecItemDelete(Self.deleteQuery(for: item) as CFDictionary)
            // An identity's certificate and key go with it, so they may be gone already.
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError(status: status)
            }
        }

        /// Every item of `itemClass`, its attributes and persistent reference, synchronized or
        /// not, in the data protection keychain.
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

        /// `item` alone, by its persistent reference.
        static func deleteQuery(for item: KeychainItem) -> [String: Any] {
            [
                kSecClass as String: item.itemClass.secClass,
                kSecValuePersistentRef as String: item.persistentReference,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                kSecUseDataProtectionKeychain as String: true
            ]
        }
    }

    extension KeychainItem {
        /// The item a `SecItemCopyMatching` result describes, or `nil` without a persistent
        /// reference, which it can't be deleted by.
        fileprivate init?(itemClass: KeychainItemClass, attributes: [String: Any]) {
            guard let reference = attributes[kSecValuePersistentRef as String] as? Data else { return nil }
            let service = itemClass == .internetPassword ? kSecAttrServer : kSecAttrService
            self.init(
                itemClass: itemClass,
                service: attributes[service as String] as? String,
                account: attributes[kSecAttrAccount as String] as? String,
                label: attributes[kSecAttrLabel as String] as? String,
                persistentReference: reference
            )
        }
    }
#endif
