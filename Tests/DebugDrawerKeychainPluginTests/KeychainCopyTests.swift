#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerKeychainPlugin
    import Foundation
    import Security
    import Testing

    @Suite
    struct KeychainCopyTests {
        @Test("Copy Value copies the mask for an item whose account, service or label matches a key pattern")
        func sensitiveMasked() throws {
            let redaction = DebugDrawerRedaction(keys: ["token"])
            let byLabel = try #require(KeychainItem(itemClass: .genericPassword, result: [
                kSecValuePersistentRef as String: Data("a".utf8), kSecAttrAccount as String: "ada",
                kSecAttrService as String: "com.example", kSecAttrLabel as String: "API token"
            ]))
            let byService = try #require(KeychainItem(itemClass: .genericPassword, result: [
                kSecValuePersistentRef as String: Data("b".utf8), kSecAttrAccount as String: "ada", kSecAttrService as String: "com.example.token"
            ]))
            let value = Result<Data?, KeychainError>.success(Data("s3cr3t".utf8))

            #expect(KeychainSelection(item: byLabel, value: value).copiedValue(redaction: redaction) == DebugDrawerRedaction.mask)
            #expect(KeychainSelection(item: byService, value: value).copiedValue(redaction: redaction) == DebugDrawerRedaction.mask)
        }

        @Test("Copy Value copies the value of an item no rule matches")
        func plainCopied() throws {
            let item = try #require(KeychainItem(itemClass: .genericPassword, result: [
                kSecValuePersistentRef as String: Data("a".utf8), kSecAttrAccount as String: "ada", kSecAttrService as String: "com.example"
            ]))
            let sut = KeychainSelection(item: item, value: .success(Data("hello".utf8)))

            let actual = sut.copiedValue(redaction: .standard)

            #expect(actual == "hello")
        }

        @Test("Copy Value copies nothing for a value that isn't text, or one that couldn't be read")
        func binaryValue() throws {
            let item = try #require(KeychainItem(itemClass: .genericPassword, result: [
                kSecValuePersistentRef as String: Data("a".utf8), kSecAttrAccount as String: "ada", kSecAttrService as String: "com.example"
            ]))
            let binary = KeychainSelection(item: item, value: .success(Data([0xFF, 0xFE])))
            let unreadable = KeychainSelection(item: item, value: .failure(KeychainError(status: errSecInteractionNotAllowed)))

            #expect(binary.copiedValue(redaction: .none) == nil)
            #expect(unreadable.copiedValue(redaction: .none) == nil)
        }

        @Test("Copy Attributes copies each attribute on a line, name then value")
        func attributesText() {
            let expected = """
            Label: Example Root CA
            Access group: TEAMID.com.example.app
            Accessible: AfterFirstUnlock
            Created: 2026-05-09T06:13:20Z
            Certificate type: 3
            Encoding: 3
            Subject: 301a3118301606035504030c0f4578616d706c6520526f6f74204341
            Issuer: 301a3118301606035504030c0f4578616d706c6520526f6f74204341
            Serial number: 018f2c
            """

            let actual = KeychainFixtures.certificate.attributesText

            #expect(actual == expected)
        }
    }
#endif
