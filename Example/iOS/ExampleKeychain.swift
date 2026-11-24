import Foundation
import Security

/// Keychain items for the Keychain plugin to show: a password in each of the example's two access
/// groups and a private key, made on request.
enum ExampleKeychain {
    /// Launched with this argument, the app adds the items before it starts.
    static let launchArgument = "-SeedKeychain"
    /// The app's own group and the shared one its entitlements name, under the team the app is
    /// signed for: FAKETEAMID in the simulator, the signing team's ID on a device.
    static var accessGroups: [String] {
        let prefix = appIdentifierPrefix() ?? "FAKETEAMID"
        return ["\(prefix).com.debugdrawer.example.ios", "\(prefix).com.debugdrawer.example.shared"]
    }

    /// The team prefix of the app's default access group, which the keychain gives an item added
    /// without one. A probe item reads it, since iOS has no public call that returns the app's own
    /// entitlements; it is deleted again at once.
    private static func appIdentifierPrefix() -> String? {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.debugdrawer.example.access-group-probe",
            kSecAttrAccount as String: "probe",
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(probe as CFDictionary)
        defer { SecItemDelete(probe as CFDictionary) }
        var added = probe
        added[kSecValueData as String] = Data()
        added[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        guard SecItemAdd(added as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [String: Any],
              let group = attributes[kSecAttrAccessGroup as String] as? String,
              let prefix = group.split(separator: ".").first
        else { return nil }
        return String(prefix)
    }
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
        let groups = accessGroups
        let passwords = [
            (service: "com.debugdrawer.example.api", account: "api-user", value: "api-token", group: groups[0]),
            (service: "com.debugdrawer.example.shared", account: "shared-user", value: "shared-token", group: groups[1])
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
