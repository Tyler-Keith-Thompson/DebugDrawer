// The user's own preferences folder is the Mac's; a simulator keeps its suites in its own.
#if os(macOS)
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    @Suite("Test suites of UserDefaults")
    struct TemporarySuiteNameTests {
        @Test("A suite named by temporarySuiteName keeps its file in the run's home folder, and none in the user's preferences")
        func fileStaysInTheRunsHomeFolder() throws {
            let name = temporarySuiteName("TemporarySuiteNameTests.\(#function)")
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let home = try #require(ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"])
            // The user's own home: Foundation's follows CFFIXED_USER_HOME.
            let userHome = try String(cString: #require(getpwuid(getuid())?.pointee.pw_dir))
            let fileName = URL(filePath: name).lastPathComponent + ".plist"
            let userPreferences = URL(filePath: userHome).appending(path: "Library/Preferences")

            defaults.set("staging", forKey: "environment")

            #expect(name.hasPrefix(URL(filePath: home, directoryHint: .isDirectory).path(percentEncoded: false)))
            #expect(FileManager.default.fileExists(atPath: name + ".plist"))
            #expect(!FileManager.default.fileExists(atPath: userPreferences.appending(path: fileName).path(percentEncoded: false)))
        }

        @Test("Every call names a new suite")
        func namesAreNew() {
            let first = temporarySuiteName("TemporarySuiteNameTests.\(#function)")
            let second = temporarySuiteName("TemporarySuiteNameTests.\(#function)")

            #expect(first != second)
        }
    }
#endif
