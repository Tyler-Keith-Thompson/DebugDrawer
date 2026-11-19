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
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appending(path: "note.txt")
            try Data("hello".utf8).write(to: file)
            let root = FileRoot(kind: .documents, url: folder)
            let model = FileBrowserModel(roots: FileRoots(available: [root]), fileSystem: LocalFileSystem())
            let sut = FileBrowserPlugin(model: model)
            drawer.registerGlobal(sut)
            model.show(.directory(root, folder))
            await model.load(model.request)
            let totalsWhileInstalled = model.folderSizes.count

            drawer.unregisterGlobal(id: sut.id)

            #expect(totalsWhileInstalled == 1)
            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(model.request.place == .roots)
            #expect(model.folderSizes.isEmpty)
            #expect(model.failure == nil)
            #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        }

        @Test("A read still running when the plugin is removed changes nothing")
        func removedWhileReading() async throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let root = FileRoot(kind: .documents, url: folder)
            let model = FileBrowserModel(roots: FileRoots(available: [root]), fileSystem: LocalFileSystem())
            let sut = FileBrowserPlugin(model: model)
            drawer.registerGlobal(sut)
            model.show(.directory(root, folder))
            let pending = model.request

            drawer.unregisterGlobal(id: sut.id)
            await model.load(pending)

            #expect(model.request.place == .roots)
            #expect(model.folderSizes.isEmpty)
        }

        @Test("Uninstalling twice is harmless, and a plugin registered again browses again")
        func uninstallTwiceThenReinstall() async throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            try Data(count: 42).write(to: folder.appending(path: "file.dat"))
            let model = FileBrowserModel(roots: FileRoots(available: [FileRoot(kind: .temporary, url: folder)]), fileSystem: LocalFileSystem())
            let sut = FileBrowserPlugin(model: model)
            drawer.registerGlobal(sut)
            drawer.unregisterGlobal(id: sut.id)

            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)
            await model.load(model.request)

            #expect(model.folderSizes[folder.filePath] == 42)
        }
    }
#endif
