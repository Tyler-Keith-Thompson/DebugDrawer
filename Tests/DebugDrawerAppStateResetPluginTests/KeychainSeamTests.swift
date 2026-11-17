#if DEBUG
    import Foundation
    @testable import DebugDrawerAppStateResetPlugin
    import Security
    import Testing

    /// The keychain probe the suite below is enabled by.
    enum KeychainAccess {
        /// Whether this process may write to the data protection keychain. It adds an item of its
        /// own and deletes it again: on the Mac a read can answer where a write is refused, so only
        /// `errSecMissingEntitlement` from a write means the keychain is out of reach.
        static var answers: Bool {
            let item: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.debugdrawer.tests.appStateReset.probe.\(UUID().uuidString)",
                kSecValueData as String: Data("probe".utf8),
                kSecUseDataProtectionKeychain as String: true
            ]
            let status = SecItemAdd(item as CFDictionary, nil)
            if status == errSecSuccess {
                var query = item
                query.removeValue(forKey: kSecValueData as String)
                SecItemDelete(query as CFDictionary)
            }
            return status != errSecMissingEntitlement
        }
    }

    /// The real keychain, through the plugin's own `_Keychain`. Each test touches only items it adds
    /// under a service no other test uses, and deletes them when it ends.
    ///
    /// The data protection keychain answers only a process signed with an application identifier.
    /// SwiftPM's runners (`just test-spm`, `just test-ios`) and Bazel's macOS `swift_test` have
    /// none and get `errSecMissingEntitlement`, and so does an `ios_unit_test` hosted by the iOS
    /// example app under `xcodebuild test`, though the same app launched on its own has a keychain.
    /// Where it gets that refusal, the suite is skipped by name rather than passing on nothing.
    @MainActor
    @Suite(
        .timeLimit(.minutes(1)),
        .enabled(if: KeychainAccess.answers, "The data protection keychain refuses a runner without an application identifier")
    )
    struct KeychainSeamTests {
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
