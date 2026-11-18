#if DEBUG
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import Testing

    @Suite
    struct FileRootsTests {
        @Test("Documents, Library, tmp, the bundle and each app group the host gives appear as roots, in that order")
        func roots() throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let group = folder.appending(path: "Group", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let locations = FakeFileLocations(
                appFolders: [
                    FileRoot(kind: .documents, url: folder.appending(path: "Documents")),
                    FileRoot(kind: .library, url: folder.appending(path: "Library")),
                    FileRoot(kind: .temporary, url: folder.appending(path: "tmp"))
                ],
                bundle: folder.appending(path: "Example.app"),
                appGroupContainers: ["group.com.example.shared": group]
            )
            let expectedTitles = ["Documents", "Library", "tmp", "App bundle", "group.com.example.shared"]

            let actual = FileRoots(locations: locations, appGroups: ["group.com.example.shared"])

            #expect(actual.available.map(\.title) == expectedTitles)
            #expect(actual.available.last?.url == group)
            #expect(actual.available.last?.kind == .appGroup("group.com.example.shared"))
            #expect(actual.missingAppGroups.isEmpty)
        }

        @Test("In a sandboxed home, Documents, Library and tmp are roots, though Application Support doesn't exist and nothing does yet")
        func sandboxedHome() throws {
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: home) }
            let locations = SystemFileLocations(
                home: home,
                temporary: home.appending(path: "tmp", directoryHint: .isDirectory),
                isSandboxed: true,
                ownFolderNames: ["com.example.shop"],
                bundle: home.appending(path: "Shop.app", directoryHint: .isDirectory)
            )
            let expectedKinds: [FileRoot.Kind] = [.documents, .library, .temporary, .bundle]
            let expectedPaths = ["Documents", "Library", "tmp", "Shop.app"].map { home.appending(path: $0).filePath }

            let actual = FileRoots(locations: locations, appGroups: []).available

            #expect(actual.map(\.kind) == expectedKinds)
            #expect(actual.map(\.url.filePath) == expectedPaths)
        }

        @Test("Outside the sandbox the app's own folders of Application Support and Caches are roots before they exist, under its bundle ID")
        func unsandboxedHomeBeforeFoldersExist() throws {
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: home) }
            let temporary = home.appending(path: "T", directoryHint: .isDirectory)
            let locations = SystemFileLocations(
                home: home, temporary: temporary, isSandboxed: false, ownFolderNames: ["com.example.shop", "Shop"], bundle: home
            )
            let expectedKinds: [FileRoot.Kind] = [.applicationSupport, .caches, .temporary]
            let expectedPaths = [
                home.appending(path: "Library/Application Support/com.example.shop").filePath,
                home.appending(path: "Library/Caches/com.example.shop").filePath,
                temporary.filePath
            ]

            let actual = locations.appFolders

            #expect(actual.map(\.kind) == expectedKinds)
            #expect(actual.map(\.url.filePath) == expectedPaths)
        }

        @Test("Outside the sandbox an existing folder named for the executable is chosen over a bundle ID's that doesn't exist")
        func unsandboxedHomeWithExecutableFolder() throws {
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let support = home.appending(path: "Library/Application Support/Shop", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: home) }
            let locations = SystemFileLocations(
                home: home, temporary: home, isSandboxed: false, ownFolderNames: ["com.example.shop", "Shop"], bundle: home
            )
            let expected = support.filePath

            let actual = locations.appFolders.first { $0.kind == .applicationSupport }?.url.filePath

            #expect(actual == expected)
        }

        @Test("Only the bundle is read-only")
        func readOnly() {
            let locations = FakeFileLocations(appFolders: [FileRoot(kind: .documents, url: URL(filePath: "/data/Documents"))])

            let actual = FileRoots(locations: locations, appGroups: []).available.filter(\.isReadOnly).map(\.kind)

            #expect(actual == [.bundle])
        }

        @Test("A group the system gives no container is listed as missing, and a group given twice appears once")
        func missingAndRepeatedGroups() {
            let container = URL(filePath: "/data/Group")
            let locations = FakeFileLocations(appGroupContainers: ["group.present": container])
            let expectedMissing = ["group.absent"]

            let actual = FileRoots(locations: locations, appGroups: ["group.present", "group.absent", "group.present"])

            #expect(actual.available.map(\.kind) == [.bundle, .appGroup("group.present")])
            #expect(actual.missingAppGroups == expectedMissing)
        }
    }
#endif
