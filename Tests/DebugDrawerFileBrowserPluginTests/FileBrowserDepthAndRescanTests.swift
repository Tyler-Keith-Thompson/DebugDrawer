#if DEBUG
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FileBrowserDepthAndRescanTests {
        @Test("A folder five levels down opens, one level read at a time, and lists what it holds")
        func folderAtDepthFive() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let deepest = folder.appending(path: "one/two/three/four/five", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: deepest, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            try Data("bottom".utf8).write(to: deepest.appending(path: "deep.txt"))
            let root = FileRoot(kind: .documents, url: folder)
            let sut = FileBrowserModel(roots: FileRoots(available: [root]), fileSystem: LocalFileSystem())
            let expectedPath = "Documents/one/two/three/four/five"
            let expectedNames = ["deep.txt"]
            var opened: [String] = []

            sut.show(.directory(root, folder))
            await sut.load(sut.request)
            // Each level lists only the folder below it, which is opened as a tap on its row would.
            while case let .directory(listing) = sut.screen, case let .loaded(contents) = listing.contents,
                  let next = contents.items.first(where: \.isDirectory) {
                opened.append(next.name)
                sut.show(.directory(root, next.url))
                await sut.load(sut.request)
            }

            guard case let .directory(listing) = sut.screen, case let .loaded(contents) = listing.contents else {
                Issue.record("Expected a loaded folder, got \(sut.screen)")
                return
            }
            #expect(opened == ["one", "two", "three", "four", "five"])
            #expect(listing.relativePath == expectedPath)
            #expect(contents.items.map(\.name) == expectedNames)
        }

        @Test("Refresh reads the folder shown again and keeps it shown, and each item keeps its identity, its path")
        func rescanKeepsPlaceAndIdentity() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let deep = folder.appending(path: "a/b/c", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            try Data("1".utf8).write(to: deep.appending(path: "first.txt"))
            let root = FileRoot(kind: .documents, url: folder)
            let sut = FileBrowserModel(roots: FileRoots(available: [root]), fileSystem: LocalFileSystem())
            func itemIDs() -> [String] {
                guard case let .directory(listing) = sut.screen, case let .loaded(contents) = listing.contents else { return [] }
                return contents.items.map(\.id)
            }
            sut.show(.directory(root, deep))
            await sut.load(sut.request)
            let before = itemIDs()
            try Data("2".utf8).write(to: deep.appending(path: "second.txt"))
            let expectedIDs = [deep.appending(path: "first.txt").filePath, deep.appending(path: "second.txt").filePath]

            sut.refresh()
            await sut.load(sut.request)

            let actual = itemIDs()
            #expect(sut.request.place == .directory(root, deep))
            #expect(before == [expectedIDs[0]])
            #expect(actual == expectedIDs)
        }

        @Test("The list of roots is empty when no root the app can change holds anything; the bundle doesn't count")
        func emptyRoots() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let documents = folder.appending(path: "Documents", directoryHint: .isDirectory)
            let bundle = folder.appending(path: "Shop.app", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            try Data("x".utf8).write(to: bundle.appending(path: "Info.plist"))
            let roots = FileRoots(available: [
                FileRoot(kind: .documents, url: documents),
                // Doesn't exist yet, so it holds nothing.
                FileRoot(kind: .library, url: folder.appending(path: "Library", directoryHint: .isDirectory)),
                FileRoot(kind: .bundle, url: bundle)
            ])
            let sut = FileBrowserModel(roots: roots, fileSystem: LocalFileSystem())

            await sut.load(sut.request)

            #expect(sut.screen == .roots(roots, isEmpty: true))

            try Data("y".utf8).write(to: documents.appending(path: "note.txt"))
            sut.refresh()
            await sut.load(sut.request)

            #expect(sut.screen == .roots(roots, isEmpty: false))
        }

        @Test("A folder the file system refuses to delete stays, with the folder shown, and the browser says why")
        func refusedFolderDelete() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let logs = folder.appending(path: "Logs", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let root = FileRoot(kind: .documents, url: folder)
            let fileSystem = FailingFileSystem()
            let sut = FileBrowserModel(roots: FileRoots(available: [root]), fileSystem: fileSystem)
            let item = try await LocalFileSystem().item(at: logs)
            sut.show(.directory(root, logs))
            let expected = FileBrowserFailure(title: "Couldn't delete Logs", reason: fileSystem.error.localizedDescription)

            await sut.delete(item)

            #expect(sut.failure == expected)
            #expect(sut.request.place == .directory(root, logs))
            #expect(FileManager.default.fileExists(atPath: logs.path(percentEncoded: false)))
        }
    }
#endif
