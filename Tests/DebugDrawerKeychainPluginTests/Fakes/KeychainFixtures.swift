#if DEBUG
    @testable import DebugDrawerKeychainPlugin
    import Foundation
    import Security

    /// Keychain items as `SecItemCopyMatching` describes them, for the views and snapshots. Each
    /// result holds a persistent reference, so `KeychainItem(itemClass:result:)` never returns
    /// `nil` for it and the force unwraps below can't fire.
    enum KeychainFixtures {
        /// 2026-05-09T06:13:20Z.
        static let created = Date(timeIntervalSinceReferenceDate: 800_000_000)
        /// A day after `created`.
        static let modified = Date(timeIntervalSinceReferenceDate: 800_086_400)

        /// A generic password for ada@example.com in com.example.App, in the app's own group.
        static let password = KeychainItem(itemClass: .genericPassword, result: [
            kSecValuePersistentRef as String: Data("password".utf8),
            kSecAttrService as String: "com.example.App",
            kSecAttrAccount as String: "ada@example.com",
            kSecAttrLabel as String: "API token",
            kSecAttrAccessGroup as String: "TEAMID.com.example.app",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock as String,
            kSecAttrSynchronizable as String: NSNumber(value: 0),
            kSecAttrCreationDate as String: created,
            kSecAttrModificationDate as String: modified,
            // The keychain's own bookkeeping, as a real item returns it: no public constant names it.
            "sha1": sha1,
            "tomb": NSNumber(value: 0)
        ])!

        /// A 20-byte digest, as the keychain's undocumented `sha1` attribute holds.
        static let sha1 = Data([
            0xDC, 0x59, 0xFE, 0xC6, 0x72, 0x3A, 0x07, 0xB9, 0x00, 0x3A, 0xC3, 0x66, 0x87, 0x21, 0x46, 0x6F, 0xC4, 0x7F, 0x25, 0xE1
        ])

        /// The DER of the name CN=Example Root CA.
        static let exampleName = Data([0x30, 0x1A, 0x31, 0x18, 0x30, 0x16, 0x06, 0x03, 0x55, 0x04, 0x03, 0x0C, 0x0F] + Array("Example Root CA".utf8))

        /// A password in a shared group.
        static let sharedPassword = KeychainItem(itemClass: .genericPassword, result: [
            kSecValuePersistentRef as String: Data("shared".utf8),
            kSecAttrService as String: "com.example.shared",
            kSecAttrAccount as String: "session",
            kSecAttrAccessGroup as String: "TEAMID.com.example.shared",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked as String,
            kSecAttrSynchronizable as String: NSNumber(value: 1),
            kSecAttrCreationDate as String: created,
            kSecAttrModificationDate as String: created
        ])!

        /// A certificate, its subject and issuer as DER.
        static let certificate = KeychainItem(itemClass: .certificate, result: [
            kSecValuePersistentRef as String: Data("certificate".utf8),
            kSecAttrLabel as String: "Example Root CA",
            kSecAttrAccessGroup as String: "TEAMID.com.example.app",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock as String,
            kSecAttrCertificateType as String: NSNumber(value: 3),
            kSecAttrCertificateEncoding as String: NSNumber(value: 3),
            kSecAttrSubject as String: exampleName,
            kSecAttrIssuer as String: exampleName,
            kSecAttrSerialNumber as String: Data([0x01, 0x8F, 0x2C]),
            kSecAttrCreationDate as String: created
        ])!

        /// A private elliptic-curve key, by its application tag.
        static let key = KeychainItem(itemClass: .key, result: [
            kSecValuePersistentRef as String: Data("key".utf8),
            kSecAttrApplicationTag as String: Data("com.example.signing".utf8),
            kSecAttrAccessGroup as String: "TEAMID.com.example.app",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
            kSecAttrKeyClass as String: NSNumber(value: 1),
            kSecAttrKeyType as String: NSNumber(value: 73),
            kSecAttrKeySizeInBits as String: NSNumber(value: 256),
            kSecAttrCanSign as String: NSNumber(value: 1),
            kSecAttrCanDecrypt as String: NSNumber(value: 0),
            kSecAttrCreationDate as String: created,
            "sha1": sha1,
            "tomb": NSNumber(value: 0)
        ])!
    }
#endif
