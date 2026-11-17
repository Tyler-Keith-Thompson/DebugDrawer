// Installing registers the plugin with the drawer of the process that runs it, so these run in a
// child process each, in a file of their own, as exit tests need one. The README's example is
// here, verbatim, rather than in DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerDatabaseBrowserPlugin
    import Foundation
    import Testing

    @Suite("Database browser install, in a child process")
    struct DatabaseBrowserInstallExitTests {
        @Test("Install registers the plugin and looks for stores in the app's folders and the added ones")
        func install() async {
            await #expect(processExitsWith: .success) {
                let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                let added = folder.appending(path: "Added", directoryHint: .isDirectory)
                try? FileManager.default.createDirectory(at: added, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: folder.appending(path: "main.sqlite").path(percentEncoded: false), contents: Data())
                FileManager.default.createFile(atPath: added.appending(path: "extra.db").path(percentEncoded: false), contents: Data())
                let model = await MainActor.run {
                    DatabaseBrowserInstallation.install(locations: FakeStoreLocations(applicationSupport: folder), additionalDirectories: [added])
                }
                await model.refresh()
                let isExpected = await MainActor.run {
                    DebugDrawer.shared.globalPlugins.contains { $0.title == "Databases" }
                        && model.listings.map(\.store.name) == ["extra.db", "main.sqlite"]
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again registers the plugin once")
        func installAgain() async {
            await #expect(processExitsWith: .success) {
                let isExpected = await MainActor.run {
                    DatabaseBrowserInstallation.install(locations: FakeStoreLocations(), additionalDirectories: [])
                    DatabaseBrowserInstallation.install(locations: FakeStoreLocations(), additionalDirectories: [])
                    return DebugDrawer.shared.globalPlugins.filter { $0.title == "Databases" }.count == 1
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("README: Databases")
        func readme() async {
            await #expect(processExitsWith: .success) {
                await MainActor.run {
                    // At startup:
                    DatabaseBrowser.install()

                    // Or with folders of the app's own as well:
                    DatabaseBrowser.install(additionalDirectories: [URL.cachesDirectory.appending(path: "Databases")])

                    let plugins = DebugDrawer.shared.globalPlugins.filter { $0.title == "Databases" }
                    exit(plugins.count == 1 ? EXIT_SUCCESS : EXIT_FAILURE)
                }
            }
        }
    }
#endif
