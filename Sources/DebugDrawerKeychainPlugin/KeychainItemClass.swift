#if DEBUG
    import Security

    // Identities are left out: each is a certificate and a private key that are listed as items of
    // their own, so listing it too would show the same two items twice.
    /// The keychain's item classes the plugin lists, each queried on its own.
    enum KeychainItemClass: CaseIterable, Hashable, Sendable {
        case genericPassword
        case internetPassword
        case certificate
        case key

        /// The `kSecClass` value.
        var secClass: CFString {
            switch self {
            case .genericPassword: kSecClassGenericPassword
            case .internetPassword: kSecClassInternetPassword
            case .certificate: kSecClassCertificate
            case .key: kSecClassKey
            }
        }

        /// What a row calls the class.
        var title: String {
            switch self {
            case .genericPassword: "Password"
            case .internetPassword: "Internet"
            case .certificate: "Certificate"
            case .key: "Key"
            }
        }

        /// Whether items of the class hold a password, which the plugin reads on demand; the
        /// value of a certificate or a key is never read.
        var holdsPassword: Bool {
            self == .genericPassword || self == .internetPassword
        }
    }
#endif
