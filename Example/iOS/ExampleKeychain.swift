import Foundation
import Security

/// Keychain items for the Keychain plugin to show: a password in each of the example's two access
/// groups and a private key, made on request.
enum ExampleKeychain {
    /// Launched with this argument, the app adds the items before it starts.
    static let launchArgument = "-SeedKeychain"
    /// The app's own group and the shared one its entitlements name.
    static let accessGroups = ["FAKETEAMID.com.debugdrawer.example.ios", "FAKETEAMID.com.debugdrawer.example.shared"]
    /// The key's application tag.
    static let keyTag = Data("com.debugdrawer.example.signing".utf8)

    /// Adds the items when launched with ``launchArgument``.
    static func install() {
        if ProcessInfo.processInfo.arguments.contains(launchArgument) {
            seed()
        }
    }

    /// Replaces the example's passwords and key: `api-user` in the app's group, `shared-user` in
    /// the shared group, and a permanent P-256 key the keychain generates. The key's private data
    /// never leaves the keychain.
    static func seed() {
        let passwords = [
            (service: "com.debugdrawer.example.api", account: "api-user", value: "api-token", group: accessGroups[0]),
            (service: "com.debugdrawer.example.shared", account: "shared-user", value: "shared-token", group: accessGroups[1])
        ]
        for password in passwords {
            let item: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: password.service,
                kSecAttrAccount as String: password.account,
                kSecAttrAccessGroup as String: password.group,
                kSecUseDataProtectionKeychain as String: true
            ]
            SecItemDelete(item as CFDictionary)
            var added = item
            added[kSecValueData as String] = Data(password.value.utf8)
            added[kSecAttrLabel as String] = "Example \(password.account)"
            added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(added as CFDictionary, nil)
        }

        let key: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(key as CFDictionary)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecUseDataProtectionKeychain as String: true,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrLabel as String: "Example signing key"
            ]
        ]
        _ = SecKeyCreateRandomKey(attributes as CFDictionary, nil)
    }
}
