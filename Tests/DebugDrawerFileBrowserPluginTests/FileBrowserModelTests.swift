#if DEBUG
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FileBrowserModelTests {
        @Test("A folder lists its folders first, then its files by name, and counts each folder's total and its own")
        func listingAndTotals() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let nested = folder.appending(path: "Bravo/Charlie", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            try Data(count: 3).write(to: folder.appending(path: "alpha.txt"))
            try Data(count: 10).write(to: folder.appending(path: "zulu.json"))
            try Data(count: 100).write(to: folder.appending(path: "Bravo/inside.bin"))
            try Data(count: 50).write(to: nested.appending(path: "deep.bin"))
            let root = FileRoot(kind: .documents, url: folder)
            let sut = FileBrowserModel(roots: FileRoots(available: [root]), fileSystem: LocalFileSystem())
            let expectedNames = ["Bravo", "alpha.txt", "zulu.json"]
            let expectedBravo: Int64 = 150
            let expectedTotal: Int64 = 163

            sut.show(.directory(root, folder))
            await sut.load(sut.request)

            guard case let .directory(listing) = sut.screen, case let .loaded(contents) = listing.contents else {
                Issue.record("Expected a loaded folder, got \(sut.screen)")
                return
            }
            #expect(contents.items.map(\.name) == expectedNames)
            #expect(sut.folderSizes[folder.appending(path: "Bravo").filePath] == expectedBravo)
            #expect(sut.folderSizes[folder.filePath] == expectedTotal)
        }

        @Test("The list of roots counts each root's total")
        func rootTotals() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            try Data(count: 42).write(to: folder.appending(path: "file.dat"))
            let sut = FileBrowserModel(roots: FileRoots(available: [FileRoot(kind: .temporary, url: folder)]), fileSystem: LocalFileSystem())
            let expected: Int64 = 42

            await sut.load(sut.request)

            #expect(sut.folderSizes[folder.filePath] == expected)
        }

        @Test("Opening a file shows its preview; Back goes to its folder, then to its parent, then to the roots")
        func openAndBack() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let sub = folder.appending(path: "Sub", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = sub.appending(path: "note.txt")
            try Data("hello".utf8).write(to: file)
            let root = FileRoot(kind: .documents, url: folder)
            let sut = FileBrowserModel(roots: FileRoots(available: [root]), fileSystem: LocalFileSystem())
            let item = try await LocalFileSystem().item(at: file)

            sut.show(.file(root, item))
            await sut.load(sut.request)

            guard case let .file(detail) = sut.screen else {
                Issue.record("Expected a file, got \(sut.screen)")
                return
            }
            #expect(detail.preview == .loaded(.text(PreviewText(lines: ["hello"]))))
            #expect(detail.relativePath == "Documents/Sub/note.txt")

            sut.back()

            #expect(sut.request.place == .directory(root, sub))

            sut.back()

            #expect(sut.request.place == .directory(root, folder))

            sut.back()

            #expect(sut.request.place == .roots)
        }

        @Test("A load that another place overtook shows nothing")
        func overtakenLoad() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let root = FileRoot(kind: .documents, url: folder)
            let sut = FileBrowserModel(roots: FileRoots(available: [root]), fileSystem: LocalFileSystem())
            sut.show(.directory(root, folder))
            let overtaken = sut.request
            sut.show(.roots)

            await sut.load(overtaken)

            #expect(sut.screen == .roots(FileRoots(available: [root])))
        }

        @Test("Deleting a file shows its folder without it; deleting the folder shown goes up")
        func delete() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let sub = folder.appending(path: "Sub", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = sub.appending(path: "old.log")
            try Data("x".utf8).write(to: file)
            let root = FileRoot(kind: .caches, url: folder)
            let sut = FileBrowserModel(roots: FileRoots(available: [root]), fileSystem: LocalFileSystem())
            let fileItem = try await LocalFileSystem().item(at: file)
            sut.show(.file(root, fileItem))

            await sut.delete(fileItem)

            #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
            #expect(sut.request.place == .directory(root, sub))

            let subItem = try await LocalFileSystem().item(at: sub)
            await sut.delete(subItem)

            #expect(!FileManager.default.fileExists(atPath: sub.path(percentEncoded: false)))
            #expect(sut.request.place.root == root)
            #expect(sut.failure == nil)
        }

        @Test("Renaming the file shown moves it and shows it under its new name")
        func rename() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appending(path: "draft.txt")
            try Data("x".utf8).write(to: file)
            let root = FileRoot(kind: .documents, url: folder)
            let sut = FileBrowserModel(roots: FileRoots(available: [root]), fileSystem: LocalFileSystem())
            let item = try await LocalFileSystem().item(at: file)
            sut.show(.file(root, item))
            let expectedName = "final.txt"

            await sut.rename(item, to: " final.txt ")

            guard case let .file(_, shown) = sut.request.place else {
                Issue.record("Expected a file, got \(sut.request.place)")
                return
            }
            #expect(shown.name == expectedName)
            #expect(FileManager.default.fileExists(atPath: folder.appending(path: expectedName).path(percentEncoded: false)))
            #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        }

        @Test("A name with a slash, or empty, renames nothing and says why")
        func invalidName() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appending(path: "keep.txt")
            try Data("x".utf8).write(to: file)
            let root = FileRoot(kind: .documents, url: folder)
            let sut = FileBrowserModel(roots: FileRoots(available: [root]), fileSystem: LocalFileSystem())
            let item = try await LocalFileSystem().item(at: file)
            sut.show(.directory(root, folder))
            let expected = "“a/b” can't be a file name."

            await sut.rename(item, to: "a/b")

            #expect(sut.failure == expected)
            #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
            #expect(!FileBrowserModel.isFileName(""))
            #expect(!FileBrowserModel.isFileName(".."))
        }

        @Test("Import copies a file into the folder shown, beside one of the same name as “name 2.ext”")
        func importFile() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let source = folder.appending(path: "Picked", directoryHint: .isDirectory)
            let target = folder.appending(path: "Target", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            try Data("new".utf8).write(to: source.appending(path: "photo.png"))
            try Data("old".utf8).write(to: target.appending(path: "photo.png"))
            let root = FileRoot(kind: .documents, url: target)
            let sut = FileBrowserModel(roots: FileRoots(available: [root]), fileSystem: LocalFileSystem())
            sut.show(.directory(root, target))
            await sut.load(sut.request)
            let expected = Data("new".utf8)

            await sut.importFile(from: source.appending(path: "photo.png"))

            let actual = try Data(contentsOf: target.appending(path: "photo 2.png"))
            #expect(actual == expected)
            #expect(try Data(contentsOf: target.appending(path: "photo.png")) == Data("old".utf8))
        }

        @Test("Nothing in the bundle is imported, renamed or deleted")
        func bundleIsReadOnly() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let bundle = folder.appending(path: "Example.app", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = bundle.appending(path: "Info.plist")
            try Data("x".utf8).write(to: file)
            try Data("y".utf8).write(to: folder.appending(path: "picked.txt"))
            let root = FileRoot(kind: .bundle, url: bundle)
            let sut = FileBrowserModel(roots: FileRoots(available: [root]), fileSystem: LocalFileSystem())
            let item = try await LocalFileSystem().item(at: file)
            sut.show(.directory(root, bundle))
            let expectedNames = ["Info.plist"]

            await sut.importFile(from: folder.appending(path: "picked.txt"))
            await sut.rename(item, to: "Renamed.plist")
            await sut.delete(item)

            let actual = try FileManager.default.contentsOfDirectory(atPath: bundle.path(percentEncoded: false))
            #expect(actual == expectedNames)
        }

        @Test("A change the file system refuses changes nothing and says why")
        func refusedChange() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appending(path: "locked.txt")
            try Data("x".utf8).write(to: file)
            let root = FileRoot(kind: .documents, url: folder)
            let fileSystem = FailingFileSystem()
            let sut = FileBrowserModel(roots: FileRoots(available: [root]), fileSystem: fileSystem)
            let item = try await LocalFileSystem().item(at: file)
            sut.show(.directory(root, folder))
            let expected = "Couldn't delete locked.txt: \(fileSystem.error.localizedDescription)"

            await sut.delete(item)

            #expect(sut.failure == expected)
            #expect(sut.request.place == .directory(root, folder))
            #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        }

        @Test("A folder that can't be read says why")
        func unreadableFolder() async {
            let missing = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: missing)
            let sut = FileBrowserModel(roots: FileRoots(available: [root]), fileSystem: LocalFileSystem())

            sut.show(.directory(root, missing))
            await sut.load(sut.request)

            guard case let .directory(listing) = sut.screen, case .failed = listing.contents else {
                Issue.record("Expected a failed folder, got \(sut.screen)")
                return
            }
        }

        @Test("A unique name counts up before the extension, and keeps a free name as it is")
        func uniqueName() {
            #expect(FileBrowserModel.uniqueName(for: "a.txt", besides: []) == "a.txt")
            #expect(FileBrowserModel.uniqueName(for: "a.txt", besides: ["a.txt", "a 2.txt"]) == "a 3.txt")
            #expect(FileBrowserModel.uniqueName(for: "Folder", besides: ["Folder"]) == "Folder 2")
        }
    }
#endif
