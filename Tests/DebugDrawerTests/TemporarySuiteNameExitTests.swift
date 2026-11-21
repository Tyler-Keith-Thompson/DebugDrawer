// Exit tests sit apart from the other tests: builds for platforms that can't start a child process
// leave this file out.
#if os(macOS)
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    @Suite("Test suites of UserDefaults across processes")
    struct TemporarySuiteNameExitTests {
        @Test("A key a child process wrote to a suite named by temporarySuiteName reads as gone once the parent removes it")
        func parentRemovesWhatTheChildWrote() async throws {
            let name = temporarySuiteName("TemporarySuiteNameExitTests.\(#function)")
            defer { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }

            await #expect(processExitsWith: .success) { [name = name as String] in
                UserDefaults(suiteName: name)?.set("staging", forKey: "environment")
            }
            let defaults = try #require(UserDefaults(suiteName: name))
            let written = defaults.string(forKey: "environment")
            defaults.removeObject(forKey: "environment")

            #expect(written == "staging")
            #expect(defaults.string(forKey: "environment") == nil)
        }
    }
#endif
