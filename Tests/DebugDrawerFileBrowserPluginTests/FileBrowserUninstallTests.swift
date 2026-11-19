#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite("File Browser drops what it read once removed from every drawer", .timeLimit(.minutes(1)))
    struct FileBrowserUninstallTests {
        private static func drawer() throws -> (DebugDrawer, () -> Void) {
            let suite = "FileBrowserUninstallTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            return (DebugDrawer(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
        }

        @Test("Unregistering removes the plugin, goes back to the roots and drops the listing and totals, leaving the files")
        func disappearsFromTheDrawer() async throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let fileSystem = FakeFileSystem(files: ["/app/Documents/note.txt": Data("hello".utf8)])
            let documents = URL(filePath: "/app/Documents", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let model = FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = transport.snapshots()
            let sut = FileBrowserPlugin(model: model)
            drawer.registerGlobal(sut)
            transport.send(FileBrowserCommand(.startReading))
            transport.send(FileBrowserCommand(.open(.directory(root, documents))))
            var totalsWhileInstalled = 0
            for await snapshot in snapshots where snapshot.folderSizes["/app/Documents"] != nil {
                totalsWhileInstalled = snapshot.folderSizes.count
                break
            }

            drawer.unregisterGlobal(id: sut.id)

            #expect(totalsWhileInstalled == 1)
            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(model.snapshot.place == .roots)
            #expect(model.snapshot.folderSizes.isEmpty)
            #expect(model.snapshot.failure == nil)
            #expect(fileSystem.exists("/app/Documents/note.txt"))
        }

        @Test("A read under way when the plugin is removed reads nothing more and changes nothing")
        func removedWhileReading() async throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let fileSystem = FakeFileSystem(files: ["/app/Documents/note.txt": Data()])
            let documents = URL(filePath: "/app/Documents", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let model = FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let sut = FileBrowserPlugin(model: model)
            drawer.registerGlobal(sut)
            transport.send(FileBrowserCommand(.startReading))
            transport.send(FileBrowserCommand(.open(.directory(root, documents))))

            // Before the folder's read gets the main actor, which the test holds until it waits.
            drawer.unregisterGlobal(id: sut.id)
            // The roots, read to the end of their totals: the view, still reading, refreshes them.
            transport.send(FileBrowserCommand(.refresh))
            var roots: FileBrowserScreen?
            for await snapshot in transport.snapshots() where snapshot.folderSizes["/app/Documents"] != nil {
                roots = snapshot.screen
                break
            }
            // Only a folder's listing reads the folder's own attributes; the roots' read doesn't.
            let folderReads = fileSystem.calls.filter { $0 == .item("/app/Documents") }

            #expect(roots == .roots(model.roots, isEmpty: false))
            #expect(folderReads.isEmpty)
        }

        @Test("Uninstalling twice is harmless, and a plugin registered again browses again")
        func uninstallTwiceThenReinstall() async throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let fileSystem = FakeFileSystem(files: ["/app/tmp/file.dat": Data(count: 42)])
            let model = FileBrowserModel(
                locations: FakeFileLocations(appFolders: [FileRoot(kind: .temporary, url: URL(filePath: "/app/tmp", directoryHint: .isDirectory))]),
                fileSystem: fileSystem
            )
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let sut = FileBrowserPlugin(model: model)
            drawer.registerGlobal(sut)
            drawer.unregisterGlobal(id: sut.id)

            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)
            transport.send(FileBrowserCommand(.startReading))
            var actual: Int64?
            for await snapshot in transport.snapshots() where snapshot.folderSizes["/app/tmp"] != nil {
                actual = snapshot.folderSizes["/app/tmp"]
                break
            }

            #expect(actual == 42)
        }
    }
#endif
