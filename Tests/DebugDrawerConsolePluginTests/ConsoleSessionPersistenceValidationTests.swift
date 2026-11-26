#if DEBUG
    import DebugDrawerConsolePlugin
    import Testing

    @Suite
    struct ConsoleSessionPersistenceValidationTests {
        @Test("A negative session count throws negativeMaxSessions")
        func negativeSessions() {
            let maxSessions = -1

            #expect(throws: ConsoleSessionPersistence.InvalidLimit.negativeMaxSessions) {
                _ = try ConsoleSessionPersistence(maxSessions: maxSessions)
            }
        }

        @Test("A size limit of 0 throws nonPositiveMaxBytes")
        func zeroBytes() {
            let maxBytes = 0

            #expect(throws: ConsoleSessionPersistence.InvalidLimit.nonPositiveMaxBytes) {
                _ = try ConsoleSessionPersistence(maxBytes: maxBytes)
            }
        }

        @Test("No kept sessions and a one-byte limit are taken: the edges of the valid ranges")
        func edges() throws {
            let expected = ConsoleSessionPersistence.off.maxSessions

            let actual = try ConsoleSessionPersistence(maxSessions: 0, maxBytes: 1)

            #expect(actual.maxSessions == expected)
            #expect(actual.maxBytes == 1)
        }
    }
#endif
