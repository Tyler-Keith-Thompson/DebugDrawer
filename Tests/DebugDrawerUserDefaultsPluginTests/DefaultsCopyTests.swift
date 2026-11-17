#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerUserDefaultsPlugin
    import Testing

    @Suite
    struct DefaultsCopyTests {
        @Test("Copy Value copies the mask for a key that matches a key pattern")
        func sensitiveMasked() {
            let entry = DefaultsEntry(key: "refreshToken", value: .string("r-123"))

            let actual = entry.copiedValue(redaction: .standard)

            #expect(actual == DebugDrawerRedaction.mask)
        }

        @Test("Copy Value copies the value of a key no rule matches")
        func plainCopied() {
            let entry = DefaultsEntry(key: "launchCount", value: .number(3))

            let actual = entry.copiedValue(redaction: .standard)

            #expect(actual == "3")
        }
    }
#endif
