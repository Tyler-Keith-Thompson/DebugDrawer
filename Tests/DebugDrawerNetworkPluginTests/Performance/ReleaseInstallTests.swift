// The release stand-in. `--config=release` builds and runs only the performance targets, so this
// is where a test is compiled without DEBUG, as an app's release build is; in debug the file is
// empty.
#if !DEBUG
    import DebugDrawer
    import DebugDrawerNetworkPlugin
    import Testing

    @Suite
    struct ReleaseInstallTests {
        @MainActor
        @Test("In release, installNetwork with a body limit compiles and captures nothing")
        func installCapturesNothing() {
            DebugDrawer.shared.installNetwork(sessions: .off, bodyLimit: 16)

            let actual = NetworkStore.shared.filteredEntries

            #expect(actual.isEmpty)
        }
    }
#endif
