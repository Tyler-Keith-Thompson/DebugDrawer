// Installing registers the plugin with the drawer of the process that runs it, so these run in a
// child process each, in a file of their own, as exit tests need one. The README's example is
// here, verbatim, rather than in DebugDrawerTests, which links core alone. None of them resets
// anything: the plugin reads the app's state only when it is shown.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerAppStateResetPlugin
    import Foundation
    import Testing

    @Suite("Reset App State install, in a child process")
    struct AppStateResetInstallExitTests {
        @Test("Install registers the plugin in Storage, every category but the app's cleanup selected, not yet read")
        func install() async {
            await #expect(processExitsWith: .success) {
                let isExpected = await MainActor.run {
                    let model = AppStateResetInstallation.install(appGroups: [], directories: [], cleanup: nil)
                    let plugin = DebugDrawer.shared.globalPlugins.first { $0.title == "Reset App State" }
                    return plugin?.category == "Storage" && model.state == .loading && !model.selection.contains(.appCleanup)
                        && model.selection.count == 6 && model.restartStyle == .relaunch
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again registers the plugin once; a cleanup from the app is selected with the rest")
        func installAgain() async {
            await #expect(processExitsWith: .success) {
                let isExpected = await MainActor.run {
                    AppStateReset.install()
                    let model = AppStateResetInstallation.install(
                        appGroups: [], directories: [], cleanup: AppStateReset.Cleanup("Close the database") {}
                    )
                    let plugins = DebugDrawer.shared.globalPlugins.count { $0.title == "Reset App State" }
                    return plugins == 1 && model.selection.contains(.appCleanup) && model.appState.cleanup?.title == "Close the database"
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("An unsandboxed Mac app's files are its own folders in Application Support and Caches, never Documents or the temporary directory")
        func unsandboxedAreas() async {
            await #expect(processExitsWith: .success) {
                let isExpected = await MainActor.run {
                    let extra = URL(filePath: "/tmp/Example Exports", directoryHint: .isDirectory)
                    let sut = AppContainer.current(appGroups: [], directories: [extra], appFolderName: "com.example.app")
                    return !AppContainer.isSandboxed
                        && sut.files.map(\.name) == ["Application Support/com.example.app", "Example Exports"]
                        && sut.files.first?.directory == URL.applicationSupportDirectory.appending(path: "com.example.app")
                        && sut.caches.map(\.directory) == [URL.cachesDirectory.appending(path: "com.example.app")]
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("README: Reset App State")
        func readme() async {
            await #expect(processExitsWith: .success) {
                let isInstalled = await MainActor.run {
                    // At startup:
                    AppStateReset.install()

                    // Or with the app's other stores, and a cleanup of its own:
                    AppStateReset.install(
                        appGroups: ["group.com.example.orders"],
                        directories: [URL.libraryDirectory.appending(path: "Exports")],
                        cleanup: AppStateReset.Cleanup("Close the orders database") {
                            OrdersDatabase.shared.close()
                        }
                    )

                    return DebugDrawer.shared.globalPlugins.count { $0.title == "Reset App State" } == 1
                }
                exit(isInstalled ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }

    /// The README example's database, which the app's cleanup closes.
    @MainActor
    final class OrdersDatabase {
        static let shared = OrdersDatabase()
        private(set) var isOpen = true

        func close() {
            isOpen = false
        }
    }
#endif
