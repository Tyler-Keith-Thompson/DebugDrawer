#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import Testing

    // The model is read and driven here as an out-of-process reader would: through its snapshot,
    // encoded and decoded, and commands, sent through a direct transport, with no view. Its file
    // system and the app's folders are hand-written fakes in memory; nothing touches the disk, the
    // home folder or an app group's container. Reads and changes land a hop after their command,
    // so each test waits on the transport's stream of snapshots for the one it expects.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FileBrowserModelTests {
        @Test("A snapshot of a folder read, with its totals, encodes to JSON and decodes equal")
        func folderSnapshotRoundTrips() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Documents/Exports/report.json": Data(count: 30), "/app/Documents/note.txt": Data(count: 5)])
            let documents = URL(filePath: "/app/Documents", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let model = FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = transport.snapshots()
            transport.send(FileBrowserCommand(.startReading))
            transport.send(FileBrowserCommand(.open(.directory(root, documents))))
            var read: FileBrowserSnapshot?
            for await snapshot in snapshots where snapshot.folderSizes["/app/Documents"] != nil {
                read = snapshot
                break
            }
            let expected = try #require(read)
            let expectedSizes: [String: Int64] = ["/app/Documents/Exports": 30, "/app/Documents": 35]

            let encoded = try JSONEncoder().encode(expected)
            let actual = try JSONDecoder().decode(FileBrowserSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.place == .directory(root, documents))
            #expect(actual.folderSizes == expectedSizes)
        }

        @Test("A snapshot of a text file and of an image, with their previews, encodes to JSON and decodes equal",
              arguments: ["/app/Documents/notes.txt", "/app/Documents/pixel.png"])
        func fileSnapshotRoundTrips(path: String) async throws {
            let png = "iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAEElEQVR4nGP4z8AARww4OQD1MQv1NXv7ggAAAABJRU5ErkJggg=="
            let fileSystem = FakeFileSystem(files: [
                "/app/Documents/notes.txt": Data("first\r\nsecond\n".utf8),
                "/app/Documents/pixel.png": try #require(Data(base64Encoded: png))
            ])
            let root = FileRoot(kind: .documents, url: URL(filePath: "/app/Documents", directoryHint: .isDirectory))
            let model = FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            let item = try await fileSystem.item(at: URL(filePath: path))
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = transport.snapshots()
            transport.send(FileBrowserCommand(.startReading))
            transport.send(FileBrowserCommand(.open(.file(root, item))))
            var read: FileBrowserSnapshot?
            for await snapshot in snapshots {
                if case let .file(detail) = snapshot.screen, detail.preview != .loading {
                    read = snapshot
                    break
                }
            }
            let expected = try #require(read)

            let encoded = try JSONEncoder().encode(expected)
            let actual = try JSONDecoder().decode(FileBrowserSnapshot.self, from: encoded)

            #expect(actual == expected)
            guard case let .file(detail) = actual.screen, case let .loaded(preview) = detail.preview else {
                Issue.record("Expected a file with its preview, got \(actual.screen)")
                return
            }
            #expect(preview.kindTitle == (path.hasSuffix(".png") ? "PNG image" : "Text"))
        }

        @Test("A snapshot before anything is read, with a missing app group, encodes to JSON and decodes equal")
        func unreadSnapshotRoundTrips() throws {
            let locations = FakeFileLocations(
                appFolders: [FileRoot(kind: .temporary, url: URL(filePath: "/app/tmp", directoryHint: .isDirectory))],
                appGroupContainers: ["group.com.example.shared": URL(filePath: "/groups/shared", directoryHint: .isDirectory)]
            )
            let sut = FileBrowserModel(
                locations: locations, appGroups: ["group.com.example.shared", "group.com.example.missing"], fileSystem: FakeFileSystem()
            )
            let expected = sut.snapshot

            let encoded = try JSONEncoder().encode(expected)
            let actual = try JSONDecoder().decode(FileBrowserSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.place == .roots)
            #expect(actual.folderSizes.isEmpty)
            #expect(actual.failure == nil)
        }

        @Test("Every command encodes to JSON and decodes equal, and decoded commands drive the model")
        func commandsRoundTrip() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Documents/old.log": Data(count: 2), "/app/Documents/keep.txt": Data(count: 1)])
            let documents = URL(filePath: "/app/Documents", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let old = try await fileSystem.item(at: URL(filePath: "/app/Documents/old.log"))
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()
            let every: [FileBrowserCommand.Action] = [
                .open(.directory(root, documents)), .back, .refresh, .startReading, .stopReading,
                .importFile(URL(filePath: "/picked/photo.png")), .rename(old, to: "new.log"), .delete(old)
            ]
            let driving: [FileBrowserCommand.Action] = [.startReading, .open(.directory(root, documents)), .delete(old)]
            let expectedNames = ["keep.txt"]

            let decoded = try every.map { action in
                try JSONDecoder().decode(FileBrowserCommand.self, from: JSONEncoder().encode(FileBrowserCommand(action))).action
            }
            for action in driving {
                try sut.send(JSONDecoder().decode(FileBrowserCommand.self, from: JSONEncoder().encode(FileBrowserCommand(action))))
            }
            var actual: [String] = []
            for await snapshot in snapshots {
                if case let .directory(listing) = snapshot.screen, case let .loaded(contents) = listing.contents {
                    actual = contents.items.map(\.name)
                    if actual == expectedNames { break }
                }
            }

            #expect(decoded == every)
            #expect(actual == expectedNames)
            #expect(!fileSystem.exists("/app/Documents/old.log"))
        }

        @Test("A folder lists its folders first, then its files by name as Finder sorts them, ignoring case")
        func sorting() async throws {
            let fileSystem = FakeFileSystem(
                files: ["/app/Documents/b.txt": Data(), "/app/Documents/File10.txt": Data(), "/app/Documents/file2.txt": Data()],
                directories: ["/app/Documents/Zeta", "/app/Documents/alpha"]
            )
            let documents = URL(filePath: "/app/Documents", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()
            let expected = ["alpha", "Zeta", "b.txt", "file2.txt", "File10.txt"]

            sut.send(FileBrowserCommand(.startReading))
            sut.send(FileBrowserCommand(.open(.directory(root, documents))))
            var actual: [String] = []
            for await snapshot in snapshots {
                if case let .directory(listing) = snapshot.screen, case let .loaded(contents) = listing.contents {
                    actual = contents.items.map(\.name)
                    break
                }
            }

            #expect(actual == expected)
        }

        @Test("The list of roots counts each root's total, and is empty when no root the app can change holds anything")
        func rootsTotalsAndEmpty() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Shop.app/Info.plist": Data(count: 7)], directories: ["/app/Documents"])
            let documents = FileRoot(kind: .documents, url: URL(filePath: "/app/Documents", directoryHint: .isDirectory))
            let library = FileRoot(kind: .library, url: URL(filePath: "/app/Library", directoryHint: .isDirectory))
            let locations = FakeFileLocations(appFolders: [documents, library], bundle: URL(filePath: "/app/Shop.app", directoryHint: .isDirectory))
            let model = FileBrowserModel(locations: locations, fileSystem: fileSystem)
            let sut = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = sut.snapshots()
            let roots = model.roots
            let expectedBundle: Int64 = 7

            sut.send(FileBrowserCommand(.startReading))
            var emptyRoots: FileBrowserScreen?
            var bundleTotal: Int64?
            for await snapshot in snapshots where snapshot.folderSizes["/app/Shop.app"] != nil {
                emptyRoots = snapshot.screen
                bundleTotal = snapshot.folderSizes["/app/Shop.app"]
                break
            }
            fileSystem.write(Data(count: 3), to: "/app/Documents/note.txt")
            sut.send(FileBrowserCommand(.refresh))
            var filledRoots: FileBrowserScreen?
            // The stream may still hold snapshots from before the refresh, with the old total.
            for await snapshot in snapshots where snapshot.folderSizes["/app/Shop.app"] != nil && snapshot.folderSizes["/app/Documents"] == 3 {
                filledRoots = snapshot.screen
                break
            }

            #expect(emptyRoots == .roots(roots, isEmpty: true))
            #expect(bundleTotal == expectedBundle)
            #expect(filledRoots == .roots(roots, isEmpty: false))
        }

        @Test("A folder counts each folder it holds at any depth, then its own total")
        func folderTotals() async throws {
            let fileSystem = FakeFileSystem(files: [
                "/app/Documents/alpha.txt": Data(count: 3), "/app/Documents/zulu.json": Data(count: 10),
                "/app/Documents/Bravo/inside.bin": Data(count: 100), "/app/Documents/Bravo/Charlie/deep.bin": Data(count: 50)
            ])
            let documents = URL(filePath: "/app/Documents", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()
            let expected: [String: Int64] = ["/app/Documents/Bravo": 150, "/app/Documents": 163]

            sut.send(FileBrowserCommand(.startReading))
            sut.send(FileBrowserCommand(.open(.directory(root, documents))))
            var actual: [String: Int64] = [:]
            for await snapshot in snapshots where snapshot.folderSizes["/app/Documents"] != nil {
                actual = snapshot.folderSizes
                break
            }

            #expect(actual == expected)
        }

        @Test("Opening a file shows its preview; Back goes to its folder, then to its parent, then to the roots")
        func openAndBack() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Documents/Sub/note.txt": Data("hello".utf8)])
            let documents = URL(filePath: "/app/Documents", directoryHint: .isDirectory)
            let sub = URL(filePath: "/app/Documents/Sub", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let item = try await fileSystem.item(at: URL(filePath: "/app/Documents/Sub/note.txt"))
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()

            sut.send(FileBrowserCommand(.startReading))
            sut.send(FileBrowserCommand(.open(.file(root, item))))
            var detail: FileDetailState?
            for await snapshot in snapshots {
                if case let .file(shown) = snapshot.screen, shown.preview != .loading {
                    detail = shown
                    break
                }
            }
            sut.send(FileBrowserCommand(.back))
            let first = sut.snapshot.place
            sut.send(FileBrowserCommand(.back))
            let second = sut.snapshot.place
            sut.send(FileBrowserCommand(.back))
            let third = sut.snapshot.place

            #expect(detail?.preview == .loaded(.text(PreviewText(lines: ["hello"]))))
            #expect(detail?.relativePath == "Documents/Sub/note.txt")
            #expect(first == .directory(root, sub))
            #expect(second == .directory(root, documents))
            #expect(third == .roots)
        }

        @Test("A read another place overtook shows nothing: the place shown last is the one read")
        func overtakenRead() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Documents/a.txt": Data(), "/app/Library/b.txt": Data()])
            let documents = FileRoot(kind: .documents, url: URL(filePath: "/app/Documents", directoryHint: .isDirectory))
            let library = FileRoot(kind: .library, url: URL(filePath: "/app/Library", directoryHint: .isDirectory))
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [documents, library]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()
            let expected = ["b.txt"]

            sut.send(FileBrowserCommand(.startReading))
            sut.send(FileBrowserCommand(.open(.directory(documents, documents.url))))
            sut.send(FileBrowserCommand(.open(.directory(library, library.url))))
            var actual: [String] = []
            for await snapshot in snapshots where snapshot.folderSizes["/app/Library"] != nil {
                if case let .directory(listing) = snapshot.screen, case let .loaded(contents) = listing.contents {
                    actual = contents.items.map(\.name)
                }
                break
            }

            #expect(actual == expected)
            #expect(sut.snapshot.place == .directory(library, library.url))
        }

        @Test("Deleting the file shown shows its folder without it; deleting the folder shown goes up")
        func delete() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Caches/Sub/old.log": Data("x".utf8)])
            let caches = URL(filePath: "/app/Caches", directoryHint: .isDirectory)
            let sub = URL(filePath: "/app/Caches/Sub", directoryHint: .isDirectory)
            let root = FileRoot(kind: .caches, url: caches)
            let file = try await fileSystem.item(at: URL(filePath: "/app/Caches/Sub/old.log"))
            let folder = try await fileSystem.item(at: sub)
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()

            sut.send(FileBrowserCommand(.startReading))
            sut.send(FileBrowserCommand(.open(.file(root, file))))
            sut.send(FileBrowserCommand(.delete(file)))
            var afterFile: [String]?
            for await snapshot in snapshots {
                if case let .directory(listing) = snapshot.screen, case let .loaded(contents) = listing.contents {
                    afterFile = contents.items.map(\.name)
                    break
                }
            }
            let placeAfterFile = sut.snapshot.place
            sut.send(FileBrowserCommand(.delete(folder)))
            for await snapshot in snapshots where snapshot.place == .directory(root, caches) {
                break
            }

            #expect(afterFile == [])
            #expect(placeAfterFile == .directory(root, sub))
            #expect(!fileSystem.exists("/app/Caches/Sub"))
            #expect(sut.snapshot.failure == nil)
        }

        @Test("A delete the file system refuses deletes nothing, keeps the folder shown and says why")
        func refusedDelete() async throws {
            let fileSystem = FakeFileSystem(directories: ["/app/Documents/Logs"])
            fileSystem.refuseChanges()
            let documents = URL(filePath: "/app/Documents", directoryHint: .isDirectory)
            let logs = URL(filePath: "/app/Documents/Logs", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let item = try await fileSystem.item(at: logs)
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()
            let expected = FileBrowserFailure(title: "Couldn't delete Logs", reason: FakeFileSystem.refusal.localizedDescription)

            sut.send(FileBrowserCommand(.open(.directory(root, logs))))
            sut.send(FileBrowserCommand(.delete(item)))
            var actual: FileBrowserFailure?
            for await snapshot in snapshots where snapshot.failure != nil {
                actual = snapshot.failure
                break
            }

            #expect(actual == expected)
            #expect(sut.snapshot.place == .directory(root, logs))
            #expect(fileSystem.exists("/app/Documents/Logs"))
        }

        @Test("Renaming the file shown moves it and shows it under its new name, trimmed")
        func rename() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Documents/draft.txt": Data("x".utf8)])
            let root = FileRoot(kind: .documents, url: URL(filePath: "/app/Documents", directoryHint: .isDirectory))
            let item = try await fileSystem.item(at: URL(filePath: "/app/Documents/draft.txt"))
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()
            let expectedName = "final.txt"

            sut.send(FileBrowserCommand(.open(.file(root, item))))
            sut.send(FileBrowserCommand(.rename(item, to: " final.txt ")))
            var actual = ""
            for await snapshot in snapshots {
                if case let .file(_, shown) = snapshot.place, shown.name != item.name {
                    actual = shown.name
                    break
                }
            }

            #expect(actual == expectedName)
            #expect(fileSystem.exists("/app/Documents/final.txt"))
            #expect(!fileSystem.exists("/app/Documents/draft.txt"))
        }

        @Test("A name with a slash, or empty, renames nothing and says why")
        func invalidName() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Documents/keep.txt": Data("x".utf8)])
            let documents = URL(filePath: "/app/Documents", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let item = try await fileSystem.item(at: URL(filePath: "/app/Documents/keep.txt"))
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()
            let expected = FileBrowserFailure(title: "Couldn't rename keep.txt", reason: "“a/b” can't be a file name.")

            sut.send(FileBrowserCommand(.open(.directory(root, documents))))
            sut.send(FileBrowserCommand(.rename(item, to: "a/b")))
            var actual: FileBrowserFailure?
            for await snapshot in snapshots where snapshot.failure != nil {
                actual = snapshot.failure
                break
            }

            let moves = fileSystem.calls.filter { if case .move = $0 { true } else { false } }
            #expect(actual == expected)
            #expect(fileSystem.exists("/app/Documents/keep.txt"))
            #expect(moves.isEmpty)
            #expect(!FileBrowserModel.isFileName(""))
            #expect(!FileBrowserModel.isFileName(".."))
        }

        @Test("Import copies a picked file into the folder shown beside one of the same name as “name 2.ext”, and again as “name 3.ext”")
        func importFile() async throws {
            let fileSystem = FakeFileSystem(files: ["/picked/photo.png": Data("new".utf8), "/app/Documents/photo.png": Data("old".utf8)])
            let documents = URL(filePath: "/app/Documents", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()
            let picked = URL(filePath: "/picked/photo.png")
            let expectedNames = ["photo 2.png", "photo 3.png", "photo.png"]

            sut.send(FileBrowserCommand(.startReading))
            sut.send(FileBrowserCommand(.open(.directory(root, documents))))
            // Sent together: the second names its copy after the first has landed.
            sut.send(FileBrowserCommand(.importFile(picked)))
            sut.send(FileBrowserCommand(.importFile(picked)))
            var actual: [String] = []
            for await snapshot in snapshots {
                if case let .directory(listing) = snapshot.screen, case let .loaded(contents) = listing.contents, contents.items.count == 3 {
                    actual = contents.items.map(\.name)
                    break
                }
            }

            #expect(actual == expectedNames)
            #expect(fileSystem.data(at: "/app/Documents/photo 3.png") == Data("new".utf8))
            #expect(fileSystem.data(at: "/app/Documents/photo.png") == Data("old".utf8))
        }

        @Test("Nothing in the bundle, and no root, is imported, renamed or deleted")
        func bundleAndRootsAreKept() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Example.app/Info.plist": Data("x".utf8), "/picked/picked.txt": Data("y".utf8)])
            let bundle = URL(filePath: "/app/Example.app", directoryHint: .isDirectory)
            let documents = FileRoot(kind: .documents, url: URL(filePath: "/app/Documents", directoryHint: .isDirectory))
            let locations = FakeFileLocations(appFolders: [documents], bundle: bundle)
            let model = FileBrowserModel(locations: locations, fileSystem: fileSystem)
            let root = try #require(model.roots.available.first { $0.isReadOnly })
            let item = try await fileSystem.item(at: URL(filePath: "/app/Example.app/Info.plist"))
            let documentsItem = FileItem(url: documents.url, isDirectory: true, size: 0, modified: nil, created: nil)
            let sut = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = sut.snapshots()

            sut.send(FileBrowserCommand(.open(.directory(root, bundle))))
            sut.send(FileBrowserCommand(.importFile(URL(filePath: "/picked/picked.txt"))))
            sut.send(FileBrowserCommand(.rename(item, to: "Renamed.plist")))
            sut.send(FileBrowserCommand(.delete(item)))
            sut.send(FileBrowserCommand(.open(.directory(documents, documents.url))))
            sut.send(FileBrowserCommand(.delete(documentsItem)))
            // A read waits for every change sent before it, so once it lands any would have run.
            sut.send(FileBrowserCommand(.startReading))
            for await snapshot in snapshots {
                if case let .directory(listing) = snapshot.screen, listing.contents != .loading { break }
            }
            let changes = fileSystem.calls.filter {
                switch $0 {
                case .remove, .move, .copy: true
                case .item, .contents, .totalSize, .read: false
                }
            }

            #expect(changes.isEmpty)
            #expect(fileSystem.exists("/app/Example.app/Info.plist"))
        }

        @Test("The app's folders, the bundle, then each app group's container in the order given, once each; a group with no container is missing")
        func appGroupRoots() {
            let documents = FileRoot(kind: .documents, url: URL(filePath: "/app/Documents", directoryHint: .isDirectory))
            let locations = FakeFileLocations(
                appFolders: [documents],
                bundle: URL(filePath: "/app/Example.app", directoryHint: .isDirectory),
                appGroupContainers: [
                    "group.com.example.orders": URL(filePath: "/groups/orders", directoryHint: .isDirectory),
                    "group.com.example.widgets": URL(filePath: "/groups/widgets", directoryHint: .isDirectory)
                ]
            )
            let sut = FileBrowserModel(locations: locations, appGroups: ["group.com.example.orders"], fileSystem: FakeFileSystem())
            let expected = FileRoots(
                available: [
                    documents,
                    FileRoot(kind: .bundle, url: URL(filePath: "/app/Example.app", directoryHint: .isDirectory)),
                    FileRoot(kind: .appGroup("group.com.example.widgets"), url: URL(filePath: "/groups/widgets", directoryHint: .isDirectory)),
                    FileRoot(kind: .appGroup("group.com.example.orders"), url: URL(filePath: "/groups/orders", directoryHint: .isDirectory))
                ],
                missingAppGroups: ["group.com.example.gone"]
            )

            sut.setAppGroups(["group.com.example.widgets", "group.com.example.gone", "group.com.example.orders", "group.com.example.widgets"])

            #expect(sut.snapshot.screen == .roots(expected, isEmpty: false))
        }

        @Test("A text file over the read limit is read up to it and shown cut short")
        func previewReads() async throws {
            let fileSystem = FakeFileSystem(files: [
                "/app/Documents/long.txt": Data(repeating: UInt8(ascii: "a"), count: FilePreview.readLimit + 10)
            ])
            let root = FileRoot(kind: .documents, url: URL(filePath: "/app/Documents", directoryHint: .isDirectory))
            let long = try await fileSystem.item(at: URL(filePath: "/app/Documents/long.txt"))
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()

            sut.send(FileBrowserCommand(.startReading))
            sut.send(FileBrowserCommand(.open(.file(root, long))))
            var preview: FilePreview?
            for await snapshot in snapshots {
                if case let .file(detail) = snapshot.screen, case let .loaded(loaded) = detail.preview {
                    preview = loaded
                    break
                }
            }

            let text = try #require(preview?.text)
            #expect(text.isTruncated)
            #expect(text.string.count == FilePreview.readLimit)
            #expect(fileSystem.calls.contains(.read("/app/Documents/long.txt", upTo: FilePreview.readLimit)))
        }

        @Test("A folder or file that can't be read says why")
        func unreadable() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Documents/Locked/secret.txt": Data("x".utf8), "/app/Documents/sealed.txt": Data("y".utf8)])
            fileSystem.makeUnreadable("/app/Documents/Locked")
            let locked = URL(filePath: "/app/Documents/Locked", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: URL(filePath: "/app/Documents", directoryHint: .isDirectory))
            let sealed = try await fileSystem.item(at: URL(filePath: "/app/Documents/sealed.txt"))
            fileSystem.makeUnreadable("/app/Documents/sealed.txt")
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()
            let expected = FakeFileSystem.unreadable.localizedDescription

            sut.send(FileBrowserCommand(.startReading))
            sut.send(FileBrowserCommand(.open(.directory(root, locked))))
            var folderReason: String?
            for await snapshot in snapshots {
                if case let .directory(listing) = snapshot.screen, case let .failed(reason) = listing.contents {
                    folderReason = reason
                    break
                }
            }
            sut.send(FileBrowserCommand(.open(.file(root, sealed))))
            var fileReason: String?
            for await snapshot in snapshots {
                if case let .file(detail) = snapshot.screen, case let .failed(reason) = detail.preview {
                    fileReason = reason
                    break
                }
            }

            #expect(folderReason == expected)
            #expect(fileReason == expected)
        }

        @Test("Nothing is read until a view starts reading, and nothing more once the last stops")
        func readsOnlyWhileRead() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Documents/a.txt": Data(), "/app/Library/b.txt": Data()])
            let documents = FileRoot(kind: .documents, url: URL(filePath: "/app/Documents", directoryHint: .isDirectory))
            let library = FileRoot(kind: .library, url: URL(filePath: "/app/Library", directoryHint: .isDirectory))
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [documents, library]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()

            sut.send(FileBrowserCommand(.open(.directory(documents, documents.url))))
            let callsBeforeReading = fileSystem.calls
            sut.send(FileBrowserCommand(.startReading))
            sut.send(FileBrowserCommand(.startReading))
            for await snapshot in snapshots where snapshot.folderSizes["/app/Documents"] != nil {
                break
            }
            sut.send(FileBrowserCommand(.stopReading))
            sut.send(FileBrowserCommand(.stopReading))
            let callsWhileRead = fileSystem.calls
            sut.send(FileBrowserCommand(.open(.directory(library, library.url))))
            sut.send(FileBrowserCommand(.refresh))

            #expect(callsBeforeReading == [])
            #expect(callsWhileRead.contains(.contents("/app/Documents")))
            #expect(fileSystem.calls == callsWhileRead)
            guard case let .directory(listing) = sut.snapshot.screen else {
                Issue.record("Expected a folder, got \(sut.snapshot.screen)")
                return
            }
            #expect(listing.contents == .loading)
        }

        @Test("Commands run in the order sent: a refresh after a delete reads the folder after the delete")
        func commandOrder() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Documents/a.txt": Data(), "/app/Documents/b.txt": Data()])
            let documents = URL(filePath: "/app/Documents", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let first = try await fileSystem.item(at: URL(filePath: "/app/Documents/a.txt"))
            let second = try await fileSystem.item(at: URL(filePath: "/app/Documents/b.txt"))
            let sut = DebugDrawerPluginTransport.direct(
                to: FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            )
            let snapshots = sut.snapshots()
            let expectedRemoved: [FakeFileSystem.Call] = [.remove("/app/Documents/a.txt"), .remove("/app/Documents/b.txt")]

            sut.send(FileBrowserCommand(.startReading))
            sut.send(FileBrowserCommand(.open(.directory(root, documents))))
            sut.send(FileBrowserCommand(.delete(first)))
            sut.send(FileBrowserCommand(.delete(second)))
            sut.send(FileBrowserCommand(.refresh))
            var listings: [[String]] = []
            for await snapshot in snapshots {
                if case let .directory(listing) = snapshot.screen, case let .loaded(contents) = listing.contents {
                    listings.append(contents.items.map(\.name))
                    if contents.items.isEmpty { break }
                }
            }
            let calls = fileSystem.calls
            let lastRemove = try #require(calls.lastIndex(of: .remove("/app/Documents/b.txt")))
            let firstListing = try #require(calls.firstIndex(of: .contents("/app/Documents")))
            let removes = calls.filter { if case .remove = $0 { true } else { false } }
            let nonEmptyListings = listings.filter { !$0.isEmpty }

            #expect(removes == expectedRemoved)
            #expect(firstListing > lastRemove)
            #expect(nonEmptyListings.isEmpty)
        }

        @Test("Each drawer that installs the plugin counts: only the last to uninstall it drops what was read")
        func installCounting() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Documents/a.txt": Data(count: 4)])
            let documents = URL(filePath: "/app/Documents", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let model = FileBrowserModel(locations: FakeFileLocations(appFolders: [root]), fileSystem: fileSystem)
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = transport.snapshots()
            // Held for the test, so no two share an address, and so an identifier.
            let drawers = (NSObject(), NSObject(), NSObject())
            let (first, second, unknown) = (ObjectIdentifier(drawers.0), ObjectIdentifier(drawers.1), ObjectIdentifier(drawers.2))
            model.install(in: first)
            model.install(in: second)
            transport.send(FileBrowserCommand(.startReading))
            transport.send(FileBrowserCommand(.open(.directory(root, documents))))
            for await snapshot in snapshots where snapshot.folderSizes["/app/Documents"] != nil {
                break
            }

            model.uninstall(from: unknown)
            model.uninstall(from: first)
            let afterFirst = model.snapshot
            model.uninstall(from: second)
            let afterSecond = model.snapshot

            #expect(afterFirst.place == .directory(root, documents))
            #expect(afterFirst.folderSizes["/app/Documents"] == 4)
            #expect(afterSecond.place == .roots)
            #expect(afterSecond.folderSizes.isEmpty)
            #expect(fileSystem.exists("/app/Documents/a.txt"))
        }

        @Test("A unique name counts up before the extension, and keeps a free name as it is")
        func uniqueName() {
            #expect(FileBrowserModel.uniqueName(for: "a.txt", besides: []) == "a.txt")
            #expect(FileBrowserModel.uniqueName(for: "a.txt", besides: ["a.txt", "a 2.txt"]) == "a 3.txt")
            #expect(FileBrowserModel.uniqueName(for: "Folder", besides: ["Folder"]) == "Folder 2")
        }
    }
#endif
