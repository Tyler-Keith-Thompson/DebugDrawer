// The data protection keychain answers only a process with an application identifier. Of the
// runners, only Bazel's iOS one has it, from //tools/test_host's entitlements (TESTED_PLATFORMS in
// scripts/modules.py); SwiftPM's iOS run (`just test-ios`) has none and gets
// errSecMissingEntitlement, and the Mac's runners are never asked, as the login keychain is the
// user's.
#if DEBUG && os(iOS) && targetEnvironment(simulator)
    @testable import DebugDrawerKeychainPlugin
    import Foundation
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
        @Test("A password added through the real keychain is listed with its value, and once deleted the keychain finds none")
        func addListDelete() throws {
            let service = "com.debugdrawer.tests.keychain.\(UUID().uuidString)"
            let match: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecUseDataProtectionKeychain as String: true
            ]
            defer { SecItemDelete(match as CFDictionary) }
            let password = GenericPassword(service: service, account: "alice", label: "API token", value: "s3cret")
            let expectedValue = Data("s3cret".utf8)
            let sut = _Keychain()

            try sut.add(password)
            let listed = try sut.items().filter { $0.service == service }
            let item = try #require(listed.first)
            let value = try sut.value(of: item)
            try sut.delete(item)
            var result: CFTypeRef?
            let actual = SecItemCopyMatching(match as CFDictionary, &result)

            #expect(listed.count == 1)
            #expect(item.itemClass == .genericPassword)
            #expect(item.account == "alice")
            #expect(item.label == "API token")
            #expect(value == expectedValue)
            #expect(actual == errSecItemNotFound)
        }
    }
#endif
