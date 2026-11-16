#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerKeychainPlugin
    import Foundation
    import Testing

    @Suite
    struct KeychainCopyTests {
        @Test("Copy Value copies the mask for an item whose account, service or label matches a key pattern")
        func sensitiveMasked() {
            let redaction = DebugDrawerRedaction(keys: ["token"])
            let byLabel = KeychainEntry(
                itemClass: "Password", account: "ada", service: "com.example", label: "API token", data: Data("s3cr3t".utf8)
            )
            let byService = KeychainEntry(
                itemClass: "Password", account: "ada", service: "com.example.token", label: nil, data: Data("s3cr3t".utf8)
            )

            #expect(byLabel.copiedValue(redaction: redaction) == DebugDrawerRedaction.mask)
            #expect(byService.copiedValue(redaction: redaction) == DebugDrawerRedaction.mask)
        }

        @Test("Copy Value copies the value of an item no rule matches")
        func plainCopied() {
            let entry = KeychainEntry(
                itemClass: "Password", account: "ada", service: "com.example", label: nil, data: Data("hello".utf8)
            )

            let actual = entry.copiedValue(redaction: .standard)

            #expect(actual == "hello")
        }

        @Test("Copy Value copies nothing for a value that isn't text")
        func binaryValue() {
            let entry = KeychainEntry(
                itemClass: "Password", account: "ada", service: "com.example", label: nil, data: Data([0xFF, 0xFE])
            )

            let actual = entry.copiedValue(redaction: .none)

            #expect(actual == nil)
        }
    }
#endif
