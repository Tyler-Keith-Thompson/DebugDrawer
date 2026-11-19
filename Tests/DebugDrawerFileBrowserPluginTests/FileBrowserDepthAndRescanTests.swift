#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FileBrowserDepthAndRescanTests {
        @Test("A folder five levels down opens, one level read at a time, and lists what it holds")
        func folderAtDepthFive() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Documents/one/two/three/four/five/deep.txt": Data("bottom".utf8)])
            let documents = URL(filePath: "/app/Documents", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()
            let expectedPath = "Documents/one/two/three/four/five"
            let expectedNames = ["deep.txt"]
            var opened: [String] = []

            sut.send(FileBrowserCommand(.startReading))
            sut.send(FileBrowserCommand(.open(.directory(root, documents))))
            // Each level lists only the folder below it, which is opened as a tap on its row would.
            // The stream may still hold snapshots from before the last open, so only the folder
            // opened last counts.
            var last: DirectoryListing?
            var shown = documents
            for await snapshot in snapshots {
                guard case let .directory(listing) = snapshot.screen, listing.url.isSameFile(as: shown),
                      case let .loaded(contents) = listing.contents else { continue }
                guard let next = contents.items.first(where: \.isDirectory) else {
                    last = listing
                    break
                }
                opened.append(next.name)
                shown = next.url
                sut.send(FileBrowserCommand(.open(.directory(root, next.url))))
            }

            guard let last, case let .loaded(contents) = last.contents else {
                Issue.record("Expected a loaded folder, got \(String(describing: last))")
                return
            }
            #expect(opened == ["one", "two", "three", "four", "five"])
            #expect(last.relativePath == expectedPath)
            #expect(contents.items.map(\.name) == expectedNames)
        }

        @Test("Refresh reads the folder shown again and keeps it shown, and each item keeps its identity, its path")
        func rescanKeepsPlaceAndIdentity() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Documents/a/b/c/first.txt": Data("1".utf8)])
            let deep = URL(filePath: "/app/Documents/a/b/c", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: URL(filePath: "/app/Documents", directoryHint: .isDirectory))
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()
            let expectedIDs = ["/app/Documents/a/b/c/first.txt", "/app/Documents/a/b/c/second.txt"]

            sut.send(FileBrowserCommand(.startReading))
            sut.send(FileBrowserCommand(.open(.directory(root, deep))))
            var before: [String] = []
            for await snapshot in snapshots {
                if case let .directory(listing) = snapshot.screen, case let .loaded(contents) = listing.contents {
                    before = contents.items.map(\.id)
                    break
                }
            }
            fileSystem.write(Data("2".utf8), to: "/app/Documents/a/b/c/second.txt")
            sut.send(FileBrowserCommand(.refresh))
            var actual: [String] = []
            // The stream may still hold snapshots from before the refresh, listing one file.
            for await snapshot in snapshots {
                if case let .directory(listing) = snapshot.screen, case let .loaded(contents) = listing.contents, contents.items.count == 2 {
                    actual = contents.items.map(\.id)
                    break
                }
            }

            #expect(sut.snapshot.place == .directory(root, deep))
            #expect(before == [expectedIDs[0]])
            #expect(actual == expectedIDs)
        }
    }
#endif
