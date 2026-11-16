#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerUserDefaultsPlugin
    import Testing

    @Suite
    struct DefaultsCopyTests {
        @Test("Copy Value copies the mask for a key that matches a key pattern")
        func sensitiveMasked() {
            let entry = DefaultsEntry(id: "refreshToken", key: "refreshToken", value: "r-123", type: "String", rawValue: "r-123")

            let actual = entry.copiedValue(redaction: .standard)

            #expect(actual == DebugDrawerRedaction.mask)
        }

        @Test("Copy Value copies the value of a key no rule matches")
        func plainCopied() {
            let entry = DefaultsEntry(id: "launchCount", key: "launchCount", value: "3", type: "Number", rawValue: 3)

            let actual = entry.copiedValue(redaction: .standard)

            #expect(actual == "3")
        }
    }
#endif
