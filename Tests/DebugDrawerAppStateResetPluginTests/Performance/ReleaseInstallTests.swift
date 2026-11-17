// The release stand-in. `--config=release` builds and runs only the performance targets, so this
// is where a test is compiled without DEBUG, as an app's release build is; in debug the file is
// empty, and AppStateResetInstallExitTests checks the opposite.
#if !DEBUG
    import DebugDrawerAppStateResetPlugin
    import Foundation
    import Testing

    @Suite
    struct ReleaseInstallTests {
        @MainActor
        @Test("In release, install takes every parameter and does nothing")
        func installDoesNothing() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            let cleanup = AppStateReset.Cleanup("Close the database") {}

            AppStateReset.install()
            AppStateReset.install(appGroups: ["group.com.example.shared"], directories: [directory], cleanup: cleanup)

            #expect(cleanup.title == "Close the database")
            #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
        }
    }
#endif
