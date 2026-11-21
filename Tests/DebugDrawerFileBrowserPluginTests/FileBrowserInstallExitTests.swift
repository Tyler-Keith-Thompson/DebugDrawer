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
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let folder = URL(filePath: "/app/Documents", directoryHint: .isDirectory)
                let locations = FakeFileLocations(
                    appFolders: [FileRoot(kind: .documents, url: folder)],
                    appGroupContainers: ["group.com.example.shared": URL(filePath: "/groups/shared", directoryHint: .isDirectory)]
                )
                let isExpected = await MainActor.run {
                    let model = FileBrowserModel(locations: locations, fileSystem: FakeFileSystem())
                    FileBrowserInstallation.install(appGroups: ["group.com.example.shared"], model: model)
                    return DebugDrawer.shared.globalPlugins.contains { $0.title == "File Browser" }
                        && model.roots.available.map(\.title) == ["Documents", "App bundle", "group.com.example.shared"]
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again registers the plugin once")
        func installAgain() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isExpected = await MainActor.run {
                    let model = FileBrowserModel(locations: FakeFileLocations(), fileSystem: FakeFileSystem())
                    FileBrowserInstallation.install(appGroups: [], model: model)
                    FileBrowserInstallation.install(appGroups: [], model: model)
                    return DebugDrawer.shared.globalPlugins.filter { $0.title == "File Browser" }.count == 1
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("README: File Browser")
        func readme() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
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
