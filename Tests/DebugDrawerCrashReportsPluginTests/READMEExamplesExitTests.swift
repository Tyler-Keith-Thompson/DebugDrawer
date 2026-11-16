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
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)

            await #expect(processExitsWith: .success) { [home = home as String] in
                // The default directory is in Application Support, under the home folder, which
                // the child moves to a temporary one.
                setenv("HOME", home, 1)
                let isInstalled = await MainActor.run {
                    // At startup, after any crash SDK has installed its own handlers:
                    CrashReports.install()

                    return DebugDrawer.shared.globalPlugins.contains { $0.title == "Crash Reports" }
                }
                exit(isInstalled ? EXIT_SUCCESS : EXIT_FAILURE)
            }

            try? FileManager.default.removeItem(atPath: home)
        }
    }
#endif
