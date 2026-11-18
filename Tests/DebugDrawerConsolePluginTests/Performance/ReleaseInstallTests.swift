// The release stand-in. `--config=release` builds and runs only the performance targets, so this
// is where a test is compiled without DEBUG, as an app's release build is; in debug the file is
// empty.
#if !DEBUG
    import DebugDrawer
    import DebugDrawerConsolePlugin
    import Testing

    @Suite
    struct ReleaseInstallTests {
        @MainActor
        @Test("In release, installConsole compiles and captures nothing")
        func installCapturesNothing() {
            DebugDrawer.shared.installConsole(sessions: .off, includeSystemDebugLogs: true)

            let actual = ConsoleLogStore.shared.filteredLines

            #expect(actual.isEmpty)
        }
    }
#endif
