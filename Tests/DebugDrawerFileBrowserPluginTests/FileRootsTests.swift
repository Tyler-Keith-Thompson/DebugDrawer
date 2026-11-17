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
