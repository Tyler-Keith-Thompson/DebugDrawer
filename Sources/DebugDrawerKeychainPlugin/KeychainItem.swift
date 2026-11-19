#if DEBUG
    import DebugDrawer
    import Foundation
    import Security

    /// A keychain item the app can read, by its attributes alone: the value of a password is read
    /// only when its detail is opened, and a key's or certificate's never.
    struct KeychainItem: Identifiable, Codable, Hashable, Sendable {
        /// Which of the keychain's classes it is.
        let itemClass: KeychainItemClass
        /// The keychain's handle on this one item, which reads, updates and deletes it and nothing
        /// else.
        let persistentReference: Data
        /// Every attribute the keychain returned worth showing, in the detail's order.
        let attributes: [KeychainAttribute]
        /// When the item was added (`kSecAttrCreationDate`), if the keychain said.
        let created: Date?
        /// When the item last changed (`kSecAttrModificationDate`), if the keychain said.
        let modified: Date?

        init(
            itemClass: KeychainItemClass,
            persistentReference: Data,
            attributes: [KeychainAttribute],
            created: Date? = nil,
            modified: Date? = nil
        ) {
            self.itemClass = itemClass
            self.persistentReference = persistentReference
            self.attributes = attributes
            self.created = created
            self.modified = modified
        }

        var id: Data {
            persistentReference
        }

        /// The account of a password, or the empty string.
        var account: String {
            self[kSecAttrAccount] ?? ""
        }

        /// The service of a generic password, the server of an internet password, or the empty
        /// string.
        var service: String {
            self[itemClass == .internetPassword ? kSecAttrServer : kSecAttrService] ?? ""
        }

        /// The item's label, if it has one.
        var label: String? {
            self[kSecAttrLabel]
        }

        /// The access group the item belongs to, if the keychain said.
        var accessGroup: String? {
            self[kSecAttrAccessGroup]
        }

        /// When the item can be read, if the plugin knows the class.
        var accessibility: KeychainAccessibility? {
            KeychainAccessibility.allCases.first { $0.title == self[kSecAttrAccessible] }
        }

        /// What the row shows first: a password's account, or a certificate's or key's label (a key's
        /// application tag without one).
        var title: String {
            if itemClass.holdsPassword, !account.isEmpty { return account }
            if let name = label ?? self[kSecAttrApplicationTag] { return name }
            return service.isEmpty ? "Unnamed \(itemClass.title.lowercased())" : service
        }

        /// What the row shows under the title: a password's service, nothing otherwise.
        var subtitle: String? {
            guard itemClass.holdsPassword, !account.isEmpty, !service.isEmpty else { return nil }
            return service
        }

        /// Whether the rules call this item's value sensitive: its account, service or label
        /// contains a key pattern.
        func isSensitive(under redaction: DebugDrawerRedaction) -> Bool {
            [account, service, label ?? ""].contains { redaction.masksKey($0) }
        }

        /// The value of the attribute `key` as the detail shows it.
        private subscript(key: CFString) -> String? {
            attributes.first { $0.key == key as String }?.value
        }
    }

    extension KeychainItem {
        /// The item a `SecItemCopyMatching` result describes, or `nil` without a persistent
        /// reference, which nothing could read or change it by.
        ///
        /// - Parameters:
        ///   - itemClass: The class the query asked for.
        ///   - result: One item's dictionary, with `kSecReturnAttributes` and
        ///     `kSecReturnPersistentRef`.
        init?(itemClass: KeychainItemClass, result: [String: Any]) {
            guard let reference = result[kSecValuePersistentRef as String] as? Data else { return nil }
            self.init(
                itemClass: itemClass,
                persistentReference: reference,
                attributes: KeychainAttribute.list(from: result, itemClass: itemClass),
                created: result[kSecAttrCreationDate as String] as? Date,
                modified: result[kSecAttrModificationDate as String] as? Date
            )
        }
    }
#endif
