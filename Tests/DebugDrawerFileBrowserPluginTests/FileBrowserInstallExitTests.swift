// Installing registers the plugin with the drawer of the process that runs it, so these run in a
// child process each, in a file of their own, as exit tests need one. The README's example is
// here, verbatim, rather than in DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import Testing

    @Suite("File browser install, in a child process")
    struct FileBrowserInstallExitTests {
        @Test("Install registers the plugin over the app's folders, the bundle and the given app groups")
        func install() async {
            await #expect(processExitsWith: .success) {
                let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                let locations = FakeFileLocations(
                    appFolders: [FileRoot(kind: .documents, url: folder)],
                    appGroupContainers: ["group.com.example.shared": folder.appending(path: "Group")]
                )
                let isExpected = await MainActor.run {
                    let model = FileBrowserInstallation.install(
                        appGroups: ["group.com.example.shared"], locations: locations, fileSystem: LocalFileSystem()
                    )
                    return DebugDrawer.shared.globalPlugins.contains { $0.title == "File Browser" }
                        && model.roots.available.map(\.title) == ["Documents", "App bundle", "group.com.example.shared"]
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again registers the plugin once")
        func installAgain() async {
            await #expect(processExitsWith: .success) {
                let isExpected = await MainActor.run {
                    FileBrowserInstallation.install(appGroups: [], locations: FakeFileLocations(), fileSystem: LocalFileSystem())
                    FileBrowserInstallation.install(appGroups: [], locations: FakeFileLocations(), fileSystem: LocalFileSystem())
                    return DebugDrawer.shared.globalPlugins.filter { $0.title == "File Browser" }.count == 1
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("README: File Browser")
        func readme() async {
            await #expect(processExitsWith: .success) {
                await MainActor.run {
                    // At startup:
                    FileBrowser.install()

                    // Or with the containers of the app's groups as well:
                    FileBrowser.install(appGroups: ["group.com.example.orders"])

                    let plugins = DebugDrawer.shared.globalPlugins.filter { $0.title == "File Browser" }
                    exit(plugins.count == 1 ? EXIT_SUCCESS : EXIT_FAILURE)
                }
            }
        }
    }
#endif
