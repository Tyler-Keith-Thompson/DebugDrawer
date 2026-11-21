// The README's Crash Reports example, verbatim, so the README cannot drift from the code. It runs
// in a child process, as installing puts the plugin's crash handlers in the process that runs it,
// and in a file of its own, as exit tests need one. It lives here rather than in DebugDrawerTests,
// which links core alone.
#if os(macOS) && DEBUG
    import DebugDrawer
    import DebugDrawerCrashReportsPlugin
    import Foundation
    import Testing

    @Suite("README examples, in a child process")
    struct READMEExamplesExitTests {
        @Test("Crash Reports")
        func crashReports() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                // The default directory is in Application Support, in the child's temporary home
                // folder (CFFIXED_USER_HOME above).
                let isInstalled = await MainActor.run {
                    // At startup, after any crash SDK has installed its own handlers:
                    CrashReports.install()

                    return DebugDrawer.shared.globalPlugins.contains { $0.title == "Crash Reports" }
                }
                exit(isInstalled ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
