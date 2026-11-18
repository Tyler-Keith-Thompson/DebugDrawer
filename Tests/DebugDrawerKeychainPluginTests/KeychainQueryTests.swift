#if DEBUG
    @testable import DebugDrawerKeychainPlugin
    import Foundation
    import Security
    import Testing

    // The exact dictionaries `_Keychain` hands SecItem*, pinned on every runner. The round trip
    // through the real keychain is KeychainSeamTests, which only Bazel's iOS run, inside
    // //tools/test_host, has a keychain for.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct KeychainQueryTests {
        @Test("Listing asks each class for attributes and persistent references, synchronized or not, in the data protection keychain, never data")
        func listQuery() {
            let expectedKeys: Set<String> = [
                kSecClass as String, kSecMatchLimit as String, kSecReturnAttributes as String, kSecReturnPersistentRef as String,
                kSecAttrSynchronizable as String, kSecUseDataProtectionKeychain as String
            ]
            let expectedClasses = [kSecClassGenericPassword, kSecClassInternetPassword, kSecClassCertificate, kSecClassKey].map { $0 as String }

            let queries = KeychainItemClass.allCases.map(_Keychain.listQuery)

            #expect(queries.compactMap { $0[kSecClass as String] as? String } == expectedClasses)
            for query in queries {
                #expect(Set(query.keys) == expectedKeys)
                #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitAll as String)
                #expect(query[kSecReturnAttributes as String] as? Bool == true)
                #expect(query[kSecReturnPersistentRef as String] as? Bool == true)
                #expect(query[kSecAttrSynchronizable as String] as? String == kSecAttrSynchronizableAny as String)
                #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
            }
        }

        @Test("An update or delete matches the item alone, by its persistent reference, in the data protection keychain")
        func itemQuery() {
            let item = KeychainFixtures.password
            let expectedKeys: Set<String> = [
                kSecClass as String, kSecValuePersistentRef as String, kSecAttrSynchronizable as String, kSecUseDataProtectionKeychain as String
            ]

            let actual = _Keychain.itemQuery(for: item)

            #expect(Set(actual.keys) == expectedKeys)
            #expect(actual[kSecClass as String] as? String == kSecClassGenericPassword as String)
            #expect(actual[kSecValuePersistentRef as String] as? Data == Data("password".utf8))
            #expect(actual[kSecAttrSynchronizable as String] as? String == kSecAttrSynchronizableAny as String)
            #expect(actual[kSecUseDataProtectionKeychain as String] as? Bool == true)
        }

        @Test("Reading a password asks for that one item's data")
        func valueQuery() {
            let item = KeychainFixtures.password
            let expectedKeys: Set<String> = [
                kSecClass as String, kSecValuePersistentRef as String, kSecAttrSynchronizable as String, kSecUseDataProtectionKeychain as String,
                kSecReturnData as String, kSecMatchLimit as String
            ]

            let actual = _Keychain.valueQuery(for: item)

            #expect(Set(actual.keys) == expectedKeys)
            #expect(actual[kSecValuePersistentRef as String] as? Data == Data("password".utf8))
            #expect(actual[kSecReturnData as String] as? Bool == true)
            #expect(actual[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
        }

        @Test("Adding writes a generic password's service, account, label, value, accessibility and group to the data protection keychain")
        func addQuery() {
            let password = GenericPassword(
                service: "com.example.App", account: "ada", label: "Token", value: "s3cr3t",
                accessGroup: "TEAMID.com.example.shared", accessibility: .afterFirstUnlockThisDeviceOnly
            )
            let expectedKeys: Set<String> = [
                kSecClass as String, kSecAttrService as String, kSecAttrAccount as String, kSecAttrLabel as String, kSecValueData as String,
                kSecAttrAccessible as String, kSecAttrAccessGroup as String, kSecUseDataProtectionKeychain as String
            ]

            let actual = _Keychain.addQuery(for: password)

            #expect(Set(actual.keys) == expectedKeys)
            #expect(actual[kSecClass as String] as? String == kSecClassGenericPassword as String)
            #expect(actual[kSecAttrService as String] as? String == "com.example.App")
            #expect(actual[kSecAttrAccount as String] as? String == "ada")
            #expect(actual[kSecAttrLabel as String] as? String == "Token")
            #expect(actual[kSecValueData as String] as? Data == Data("s3cr3t".utf8))
            #expect(actual[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
            #expect(actual[kSecAttrAccessGroup as String] as? String == "TEAMID.com.example.shared")
            #expect(actual[kSecUseDataProtectionKeychain as String] as? Bool == true)
        }

        @Test("A password added with no label and no group names neither, so it goes in the app's default group")
        func addQueryDefaults() {
            let password = GenericPassword(service: "com.example.App", account: "ada", value: "s3cr3t")

            let actual = _Keychain.addQuery(for: password)

            #expect(actual[kSecAttrLabel as String] == nil)
            #expect(actual[kSecAttrAccessGroup as String] == nil)
            #expect(actual[kSecAttrSynchronizable as String] == nil)
            #expect(actual[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlocked as String)
        }

        @Test("An edit writes the service, account, label, value and accessibility, and leaves the group alone")
        func updatedAttributes() {
            let password = GenericPassword(
                service: "com.example.App", account: "ada", label: "", value: "new", accessGroup: "TEAMID.com.example.shared",
                accessibility: .whenUnlocked
            )
            let expectedKeys: Set<String> = [
                kSecAttrService as String, kSecAttrAccount as String, kSecAttrLabel as String, kSecValueData as String, kSecAttrAccessible as String
            ]

            let actual = _Keychain.updatedAttributes(for: password)

            #expect(Set(actual.keys) == expectedKeys)
            #expect(actual[kSecValueData as String] as? Data == Data("new".utf8))
            #expect(actual[kSecAttrLabel as String] as? String == "")
        }

        @Test("A key's or certificate's value is never read: the real keychain answers nil without asking")
        func keyValueNeverRead() throws {
            let sut = _Keychain()

            let key = try sut.value(of: KeychainFixtures.key)
            let certificate = try sut.value(of: KeychainFixtures.certificate)

            #expect(key == nil)
            #expect(certificate == nil)
        }

        @Test("A result without a persistent reference makes no item, since nothing could reach it")
        func noReference() {
            let result: [String: Any] = [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"]

            let actual = KeychainItem(itemClass: .genericPassword, result: result)

            #expect(actual == nil)
        }
    }
#endif
