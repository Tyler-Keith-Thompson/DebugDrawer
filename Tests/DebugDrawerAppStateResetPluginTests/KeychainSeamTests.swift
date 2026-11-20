// The data protection keychain answers only a process with an application identifier. Of the
// runners, only Bazel's iOS one has it, from //tools/test_host's entitlements (TESTED_PLATFORMS in
// scripts/modules.py); SwiftPM's iOS run (`just test-ios`) has none and gets
// errSecMissingEntitlement, and the Mac's runners are never asked, as the login keychain is the
// user's.
#if DEBUG && os(iOS) && targetEnvironment(simulator)
    import Foundation
    @testable import DebugDrawerAppStateResetPlugin
    @testable import DebugDrawerAppStateReset
    import Security
    import Testing

    /// Whether the tests run inside //tools/test_host, by its bundle identifier.
    private let isInTestHost = Bundle.main.bundleIdentifier == "com.debugdrawer.testhost"

    /// The real keychain, through the plugin's own `_Keychain`. Each test touches only items it adds
    /// under a service no other run uses, and deletes them when it ends.
    @MainActor
    @Suite(
        .timeLimit(.minutes(1)),
        .enabled(if: isInTestHost, "Only //tools/test_host's entitlements give a test process a keychain")
    )
    struct KeychainSeamTests {
        @Test("The real keychain lists a generic password added through SecItemAdd and deletes it, so the keychain then finds none")
        func addListDelete() throws {
            let service = "com.debugdrawer.tests.appStateReset.\(UUID().uuidString)"
            let expectedAccount = "alice"
            let match: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecUseDataProtectionKeychain as String: true
            ]
            defer { SecItemDelete(match as CFDictionary) }
            let attributes = match.merging([
                kSecAttrAccount as String: expectedAccount,
                kSecValueData as String: Data("secret".utf8)
            ]) { _, new in new }
            let added = SecItemAdd(attributes as CFDictionary, nil)
            try #require(added == errSecSuccess, "SecItemAdd returned \(added)")
            let sut = _Keychain()

            let listed = try sut.items().filter { $0.service == service }
            let item = try #require(listed.first)
            try sut.delete(item)
            var result: CFTypeRef?
            let actual = SecItemCopyMatching(match as CFDictionary, &result)

            #expect(listed.count == 1)
            #expect(item.itemClass == .genericPassword)
            #expect(item.account == expectedAccount)
            #expect(actual == errSecItemNotFound)
        }

        @Test("The keychain lists the items the app added, by service and account, and deletes the one asked for alone")
        func listAndDeleteOne() throws {
            let service = "com.debugdrawer.tests.appStateReset.\(UUID().uuidString)"
            defer {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecUseDataProtectionKeychain as String: true
                ]
                SecItemDelete(query as CFDictionary)
            }
            for account in ["alice", "bob"] {
                let item: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                    kSecValueData as String: Data("token".utf8),
                    kSecUseDataProtectionKeychain as String: true
                ]
                try #require(SecItemAdd(item as CFDictionary, nil) == errSecSuccess)
            }
            let sut = _Keychain()
            let listed = try sut.items().filter { $0.service == service }
            let alice = try #require(listed.first { $0.account == "alice" })
            let expectedNames = ["\(service) · alice", "\(service) · bob"]

            try sut.delete(alice)
            let actual = try sut.items().filter { $0.service == service }.compactMap(\.account)

            #expect(listed.map(\.name).sorted() == expectedNames)
            #expect(actual == ["bob"])
        }

        @Test("Deleting an item already gone is no error")
        func deleteGone() throws {
            let service = "com.debugdrawer.tests.appStateReset.\(UUID().uuidString)"
            let item: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "alice",
                kSecValueData as String: Data("token".utf8),
                kSecUseDataProtectionKeychain as String: true
            ]
            try #require(SecItemAdd(item as CFDictionary, nil) == errSecSuccess)
            let sut = _Keychain()
            let listed = try #require(try sut.items().first { $0.service == service })
            try sut.delete(listed)

            try sut.delete(listed)

            #expect(try sut.items().contains { $0.service == service } == false)
        }

        @Test("No item can be put in an access group the app's entitlements don't name, so the reset can't reach another app's")
        func otherAppsGroupIsOutOfReach() {
            // An item outside the app's scope can't be made from inside it: the keychain refuses a
            // group the entitlements don't name. That refusal is the scoping that keeps another app's
            // items out of the plugin's queries, which name no group and so match the app's own.
            let item: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.debugdrawer.tests.appStateReset.\(UUID().uuidString)",
                kSecAttrAccount as String: "another-app",
                kSecAttrAccessGroup as String: "ABCDE12345.com.example.another-app",
                kSecValueData as String: Data("token".utf8),
                kSecUseDataProtectionKeychain as String: true
            ]

            let actual = SecItemAdd(item as CFDictionary, nil)

            #expect(actual == errSecMissingEntitlement)
        }
    }
#endif
