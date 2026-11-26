#if DEBUG
    import DebugDrawer
    import DebugDrawerNetworkPlugin
    import Testing

    // In-process: installNetwork checks its arguments before it registers the URL protocol or
    // touches a shared model, so a refused install changes nothing in the process.
    @MainActor
    @Suite
    struct NetworkInstallValidationTests {
        @Test("A negative body limit throws negativeBodyLimit")
        func negativeBodyLimit() {
            let bodyLimit = -1

            #expect(throws: NetworkPlugin.InvalidInstallation.negativeBodyLimit) {
                try DebugDrawer.shared.installNetwork(sessions: .off, bodyLimit: bodyLimit)
            }
        }

        @Test("Bypassed text that isn't a host throws bypassedTextNotAHost")
        func bypassedTextNotAHost() {
            let bypassing = ["*.example.com"]

            #expect(throws: NetworkPlugin.InvalidInstallation.bypassedTextNotAHost) {
                try DebugDrawer.shared.installNetwork(bypassing: bypassing, sessions: .off)
            }
        }

        @Test("One malformed host among good ones throws bypassedTextNotAHost")
        func oneMalformedAmongGood() {
            let bypassing = ["pinned.example.com", "not a host"]

            #expect(throws: NetworkPlugin.InvalidInstallation.bypassedTextNotAHost) {
                try DebugDrawer.shared.installNetwork(bypassing: bypassing, sessions: .off)
            }
        }

        @Test("A negative session count throws negativeMaxSessions")
        func negativeSessions() {
            let maxSessions = -1

            #expect(throws: NetworkSessionPersistence.InvalidLimit.negativeMaxSessions) {
                _ = try NetworkSessionPersistence(maxSessions: maxSessions)
            }
        }

        @Test("A size limit of 0 throws nonPositiveMaxBytes")
        func zeroBytes() {
            let maxBytes = 0

            #expect(throws: NetworkSessionPersistence.InvalidLimit.nonPositiveMaxBytes) {
                _ = try NetworkSessionPersistence(maxBytes: maxBytes)
            }
        }

        @Test("No kept sessions and a one-byte limit are taken: the edges of the valid ranges")
        func edges() throws {
            let expected = NetworkSessionPersistence.off.maxSessions

            let actual = try NetworkSessionPersistence(maxSessions: 0, maxBytes: 1)

            #expect(actual.maxSessions == expected)
            #expect(actual.maxBytes == 1)
        }
    }
#endif
