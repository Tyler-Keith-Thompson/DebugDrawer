// Exit tests sit apart from the other tests: builds for platforms that can't start a child process
// leave this file out.
#if os(macOS)
    import DebugDrawerAnalytics
    import Testing

    @Suite
    struct AnalyticsRedactionExitTests {
        @Test("A value pattern that isn't a regular expression traps, rather than letting what it was meant to mask through")
        func invalidPatternTraps() async {
            await #expect(processExitsWith: .failure) {
                _ = AnalyticsRedaction(values: ["(unclosed"])
            }
        }

        @Test("Adding a value pattern that isn't a regular expression traps")
        func invalidAddedPatternTraps() async {
            await #expect(processExitsWith: .failure) {
                _ = AnalyticsRedaction.standard.adding(values: ["[z-a]"])
            }
        }
    }
#endif
