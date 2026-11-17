#if DEBUG
    @testable import DebugDrawerKeychainPlugin
    import Foundation
    import Security
    import Testing

    @Suite
    struct KeychainAttributeTests {
        @Test("A password's attributes read in words: accessibility by its class, synchronizable as Yes or No, dates in ISO 8601")
        func passwordAttributes() {
            let result: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword as String,
                kSecValuePersistentRef as String: Data("reference".utf8),
                kSecAttrAccount as String: "ada",
                kSecAttrService as String: "com.example.App",
                kSecAttrAccessGroup as String: "TEAMID.com.example.app",
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock as String,
                kSecAttrSynchronizable as String: NSNumber(value: 1),
                kSecAttrCreationDate as String: Date(timeIntervalSinceReferenceDate: 0),
                kSecAttrModificationDate as String: Date(timeIntervalSinceReferenceDate: 60)
            ]
            let expected = [
                "Service: com.example.App", "Account: ada", "Access group: TEAMID.com.example.app", "Accessible: AfterFirstUnlock",
                "Synchronizable: Yes", "Created: 2001-01-01T00:00:00Z", "Modified: 2001-01-01T00:01:00Z"
            ]

            let actual = KeychainAttribute.list(from: result, itemClass: .genericPassword).map { "\($0.name): \($0.value)" }

            #expect(actual == expected)
        }

        @Test("A key's class, type, size and abilities read in words, and its application tag as text")
        func keyAttributes() {
            let result: [String: Any] = [
                kSecAttrApplicationTag as String: Data("com.example.signing".utf8),
                kSecAttrKeyClass as String: NSNumber(value: 1),
                kSecAttrKeyType as String: NSNumber(value: 73),
                kSecAttrKeySizeInBits as String: NSNumber(value: 256),
                kSecAttrCanSign as String: NSNumber(value: 1),
                kSecAttrCanDecrypt as String: NSNumber(value: 0)
            ]
            let expected = [
                "Key class: Private", "Key size: 256", "Application tag: com.example.signing", "Can decrypt: No", "Can sign: Yes",
                "Key type: Elliptic curve"
            ].sorted()

            let actual = KeychainAttribute.list(from: result, itemClass: .key).map { "\($0.name): \($0.value)" }.sorted()

            #expect(actual == expected)
        }

        @Test("A certificate's DER subject and serial number show every byte in hexadecimal, as one token with no spaces")
        func certificateAttributes() {
            let result: [String: Any] = [
                kSecAttrLabel as String: "Example Root CA",
                kSecAttrSerialNumber as String: Data([0x01, 0x8F, 0x2C]),
                kSecAttrSubject as String: Data([0x30, 0x00] + Array(repeating: UInt8(0x41), count: 30))
            ]
            let expectedSubject = "3000" + String(repeating: "41", count: 30)

            let actual = KeychainAttribute.list(from: result, itemClass: .certificate).map { "\($0.name): \($0.value)" }

            #expect(actual == ["Label: Example Root CA", "Subject: \(expectedSubject)", "Serial number: 018f2c"])
        }

        @Test("Attributes with a public kSecAttr constant are documented and named in words; the keychain's bookkeeping keeps its raw key")
        func documentedAttributes() {
            let result: [String: Any] = [
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock as String,
                kSecAttrSynchronizable as String: NSNumber(value: 0),
                kSecAttrCreationDate as String: Date(timeIntervalSinceReferenceDate: 0),
                kSecAttrIsInvisible as String: NSNumber(value: 1),
                "sha1": Data([0xDC, 0x59, 0x00]),
                "tomb": NSNumber(value: 0),
                "persistref": Data([0x00, 0x01])
            ]
            let expectedDocumented = ["Accessible", "Synchronizable", "Created", "Invisible"]
            let expectedOther = ["persistref: 0001", "sha1: dc5900", "tomb: 0"]

            let attributes = KeychainAttribute.list(from: result, itemClass: .genericPassword)
            let documented = attributes.filter(\.isDocumented).map(\.name)
            let other = attributes.filter { !$0.isDocumented }.map { "\($0.name): \($0.value)" }

            #expect(documented == expectedDocumented)
            #expect(other == expectedOther)
        }

        @Test("A password's type keeps the name Type, not Key type, though both are the attribute `type`")
        func passwordType() {
            let result: [String: Any] = [kSecAttrType as String: NSNumber(value: 73)]

            let actual = KeychainAttribute.list(from: result, itemClass: .genericPassword).map { "\($0.name): \($0.value)" }

            #expect(actual == ["Type: 73"])
        }

        @Test("The class, value and references are left out, empty values dropped, and unknown attributes follow by key")
        func hiddenAndUnknown() {
            let result: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword as String,
                kSecValueData as String: Data("s3cr3t".utf8),
                kSecValuePersistentRef as String: Data("reference".utf8),
                kSecAttrLabel as String: "",
                kSecAttrGeneric as String: Data(),
                "zzzz": "last",
                "musr": "first",
                kSecAttrAccount as String: "ada"
            ]

            let actual = KeychainAttribute.list(from: result, itemClass: .genericPassword).map { "\($0.name): \($0.value)" }

            #expect(actual == ["Account: ada", "musr: first", "zzzz: last"])
        }

        @Test("An attribute of another type, such as an access control object, shows its description, not an optional's")
        func otherType() throws {
            let url = try #require(URL(string: "https://example.com"))
            let result: [String: Any] = ["zobj": url as NSURL]

            let actual = KeychainAttribute.list(from: result, itemClass: .genericPassword).map(\.value)

            #expect(actual == ["https://example.com"])
        }

        @Test("An access control object shows as Set, not its internal description")
        func accessControl() throws {
            let control = try #require(SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlocked, [], nil))
            let result: [String: Any] = [kSecAttrAccessControl as String: control]

            let actual = KeychainAttribute.list(from: result, itemClass: .genericPassword).map { "\($0.name): \($0.value)" }

            #expect(actual == ["Access control: Set"])
        }

        @Test("An accessibility the plugin doesn't know shows its raw value")
        func unknownAccessibility() {
            let result: [String: Any] = [kSecAttrAccessible as String: "dku"]

            let actual = KeychainAttribute.list(from: result, itemClass: .genericPassword).map(\.value)

            #expect(actual == ["dku"])
        }

        @Test("A row names a password by account and service, a certificate by label, a key by tag, and an unnamed item by class")
        func titles() {
            let unnamed = KeychainItem(itemClass: .key, persistentReference: Data(), attributes: [])

            #expect(KeychainFixtures.password.title == "ada@example.com")
            #expect(KeychainFixtures.password.subtitle == "com.example.App")
            #expect(KeychainFixtures.certificate.title == "Example Root CA")
            #expect(KeychainFixtures.certificate.subtitle == nil)
            #expect(KeychainFixtures.key.title == "com.example.signing")
            #expect(unnamed.title == "Unnamed key")
        }
    }
#endif
