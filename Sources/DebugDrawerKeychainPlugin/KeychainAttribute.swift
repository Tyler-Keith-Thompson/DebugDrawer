#if DEBUG
    import Foundation
    import Security

    /// One attribute of a keychain item as the detail shows it: its name and its value in words.
    struct KeychainAttribute: Codable, Hashable, Sendable {
        /// The attribute's key in a `SecItemCopyMatching` result (`pdmn`, `cdat`).
        let key: String
        /// What the detail calls it: a word label ("Accessible", "Created") for an attribute with a
        /// public `kSecAttr` constant, the raw key (`sha1`, `tomb`) otherwise.
        let name: String
        /// The value as text: a date in ISO 8601, a flag as Yes or No, bytes that aren't text in
        /// hexadecimal, in full.
        let value: String
        /// Whether Apple documents the attribute with a public `kSecAttr` constant. The detail
        /// lists the others apart, under Other attributes, as the keychain's own bookkeeping.
        let isDocumented: Bool
    }

    extension KeychainAttribute {
        /// The attributes in `result` worth showing, the well-known ones first in a fixed order,
        /// then the rest by key. The class, the value and references are left out, and so are empty
        /// strings and data.
        ///
        /// - Parameters:
        ///   - result: One item's dictionary from `SecItemCopyMatching` with `kSecReturnAttributes`.
        ///   - itemClass: The item's class, which names `type` (a key's type, or a password's).
        static func list(from result: [String: Any], itemClass: KeychainItemClass) -> [KeychainAttribute] {
            let shown = result.filter { !hiddenKeys.contains($0.key) }
            let known = knownNames.compactMap { key, name -> KeychainAttribute? in
                guard let raw = shown[key] else { return nil }
                let name = displayName(for: key, default: name, in: itemClass)
                return KeychainAttribute(key: key, raw: raw, name: name, isDocumented: true, in: itemClass)
            }
            let knownKeys = Set(knownNames.map(\.key))
            let others = shown.filter { !knownKeys.contains($0.key) }.sorted { $0.key < $1.key }.compactMap { key, raw in
                KeychainAttribute(key: key, raw: raw, name: key, isDocumented: false, in: itemClass)
            }
            return known + others
        }

        /// The attribute named `raw`'s value as text, or `nil` when it is empty.
        private init?(key: String, raw: Any, name: String, isDocumented: Bool, in itemClass: KeychainItemClass) {
            guard let value = Self.text(of: raw, key: key, in: itemClass) else { return nil }
            self.init(key: key, name: name, value: value, isDocumented: isDocumented)
        }

        // `type` is both kSecAttrType (a password's four-character type) and kSecAttrKeyType.
        private static func displayName(for key: String, default name: String, in itemClass: KeychainItemClass) -> String {
            key == kSecAttrKeyType as String && itemClass == .key ? "Key type" : name
        }

        /// Keys the detail shows elsewhere or never: the class, and the value and references the
        /// query asks for.
        private static let hiddenKeys: Set<String> = [
            kSecClass as String, kSecValueData as String, kSecValuePersistentRef as String, kSecValueRef as String
        ]

        /// The attributes Apple documents, in the order the detail lists them. Persistent
        /// reference (`persistref`) is left out on purpose: it is the item's handle, which the
        /// plugin keeps already, and reads as bookkeeping beside the others.
        private static let knownNames: [(key: String, name: String)] = [
            (kSecAttrService as String, "Service"),
            (kSecAttrServer as String, "Server"),
            (kSecAttrAccount as String, "Account"),
            (kSecAttrLabel as String, "Label"),
            (kSecAttrAccessGroup as String, "Access group"),
            (kSecAttrAccessible as String, "Accessible"),
            (kSecAttrAccessControl as String, "Access control"),
            (kSecAttrSynchronizable as String, "Synchronizable"),
            (kSecAttrSyncViewHint as String, "Sync view"),
            (kSecAttrCreationDate as String, "Created"),
            (kSecAttrModificationDate as String, "Modified"),
            (kSecAttrDescription as String, "Description"),
            (kSecAttrComment as String, "Comment"),
            (kSecAttrGeneric as String, "Generic"),
            (kSecAttrCreator as String, "Creator"),
            (kSecAttrType as String, "Type"),
            (kSecAttrIsInvisible as String, "Invisible"),
            (kSecAttrIsNegative as String, "Negative"),
            (kSecAttrProtocol as String, "Protocol"),
            (kSecAttrPort as String, "Port"),
            (kSecAttrPath as String, "Path"),
            (kSecAttrSecurityDomain as String, "Security domain"),
            (kSecAttrAuthenticationType as String, "Authentication"),
            (kSecAttrKeyClass as String, "Key class"),
            (kSecAttrKeySizeInBits as String, "Key size"),
            (kSecAttrEffectiveKeySize as String, "Effective size"),
            (kSecAttrApplicationTag as String, "Application tag"),
            (kSecAttrApplicationLabel as String, "Application label"),
            (kSecAttrTokenID as String, "Token"),
            (kSecAttrIsPermanent as String, "Permanent"),
            (kSecAttrCanEncrypt as String, "Can encrypt"),
            (kSecAttrCanDecrypt as String, "Can decrypt"),
            (kSecAttrCanDerive as String, "Can derive"),
            (kSecAttrCanSign as String, "Can sign"),
            (kSecAttrCanVerify as String, "Can verify"),
            (kSecAttrCanWrap as String, "Can wrap"),
            (kSecAttrCanUnwrap as String, "Can unwrap"),
            (kSecAttrCertificateType as String, "Certificate type"),
            (kSecAttrCertificateEncoding as String, "Encoding"),
            (kSecAttrSubject as String, "Subject"),
            (kSecAttrIssuer as String, "Issuer"),
            (kSecAttrSerialNumber as String, "Serial number"),
            (kSecAttrSubjectKeyID as String, "Subject key ID"),
            (kSecAttrPublicKeyHash as String, "Public key hash")
        ]

        /// Attributes whose value is a number that means yes or no.
        private static let flagKeys: Set<String> = [
            kSecAttrSynchronizable, kSecAttrIsPermanent, kSecAttrCanEncrypt, kSecAttrCanDecrypt, kSecAttrCanDerive,
            kSecAttrCanSign, kSecAttrCanVerify, kSecAttrCanWrap, kSecAttrCanUnwrap, kSecAttrIsInvisible, kSecAttrIsNegative
        ].reduce(into: []) { $0.insert($1 as String) }

        private static func text(of raw: Any, key: String, in itemClass: KeychainItemClass) -> String? {
            switch raw {
            case let date as Date:
                return date.formatted(.iso8601)
            case let number as NSNumber where flagKeys.contains(key) || CFGetTypeID(number) == CFBooleanGetTypeID():
                return number.boolValue ? "Yes" : "No"
            case let number as NSNumber:
                return words(for: number.stringValue, key: key, in: itemClass)
            case let string as String:
                return string.isEmpty ? nil : words(for: string, key: key, in: itemClass)
            case let data as Data:
                return data.isEmpty ? nil : data.keychainText
            // An access control object describes itself only by an internal code (`ak`), and no
            // public API reads its flags, so the detail says it is there.
            case let object as CFTypeRef where CFGetTypeID(object) == SecAccessControlGetTypeID():
                return "Set"
            default:
                return String(describing: raw)
            }
        }

        /// A string or number attribute in words where its value is a constant: an accessibility
        /// class, a key's class or type. The keychain returns a key's class and type as numbers.
        private static func words(for string: String, key: String, in itemClass: KeychainItemClass) -> String {
            let constants: [(value: CFString, word: String)]
            if key == kSecAttrAccessible as String {
                return KeychainAccessibility(secValue: string)?.title ?? string
            } else if key == kSecAttrKeyClass as String {
                constants = [(kSecAttrKeyClassPublic, "Public"), (kSecAttrKeyClassPrivate, "Private"), (kSecAttrKeyClassSymmetric, "Symmetric")]
            } else if key == kSecAttrKeyType as String, itemClass == .key {
                constants = [(kSecAttrKeyTypeRSA, "RSA"), (kSecAttrKeyTypeECSECPrimeRandom, "Elliptic curve")]
            } else {
                return string
            }
            return constants.first { $0.value as String == string }?.word ?? string
        }
    }

    extension Data {
        /// The bytes as UTF-8 text when they are printable text, otherwise every byte in
        /// hexadecimal with no spaces ("dc59fec6"). As one token, the detail's row keeps it to one
        /// line cut in the middle, and Copy Attributes still copies it whole.
        fileprivate var keychainText: String {
            if let text = String(data: self, encoding: .utf8), !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
                return text
            }
            return map { String(format: "%02x", $0) }.joined()
        }
    }
#endif
