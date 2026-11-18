// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FileBrowserEmptyAndFailureViewTests {
        @Test("When no root holds anything the list of roots says so above the roots, which still open")
        func emptyRoots() throws {
            let roots = FileRoots(available: [FileRoot(kind: .documents, url: URL(filePath: "/data/Documents"))])
            let sut = FileBrowserView(screen: .roots(roots, isEmpty: true), folderSizes: [:], actions: FileBrowserActions())
            let expected = "No files yet"

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(try sut.inspect().findAll(FileListRow.self).count == 1)
        }

        @Test("A list of roots that holds something shows no empty state")
        func rootsWithFiles() throws {
            let roots = FileRoots(available: [FileRoot(kind: .documents, url: URL(filePath: "/data/Documents"))])
            let sut = FileBrowserView(screen: .roots(roots, isEmpty: false), folderSizes: [:], actions: FileBrowserActions())

            #expect(throws: (any Error).self) { try sut.inspect().find(text: "No files yet") }
        }

        @Test("An empty folder shows the empty state, and still offers Import")
        func emptyFolder() throws {
            let documents = URL(filePath: "/data/Documents", directoryHint: .isDirectory)
            let directory = FileItem(url: documents, isDirectory: true, size: 0, modified: nil, created: nil)
            let listing = DirectoryListing(
                root: FileRoot(kind: .documents, url: documents), url: documents,
                contents: .loaded(DirectoryContents(directory: directory, items: []))
            )
            let sut = DirectoryView(listing: listing, folderSizes: [:], actions: FileBrowserActions())
            let expected = "Empty folder"

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(try sut.inspect().find(button: "Import…").labelView().text().string() == "Import…")
        }

        @Test("A refused delete shows what failed and why, under the folder")
        func deleteFailure() throws {
            let documents = URL(filePath: "/data/Documents", directoryHint: .isDirectory)
            let directory = FileItem(url: documents, isDirectory: true, size: 0, modified: nil, created: nil)
            let listing = DirectoryListing(
                root: FileRoot(kind: .documents, url: documents), url: documents,
                contents: .loaded(DirectoryContents(directory: directory, items: []))
            )
            let failure = FileBrowserFailure(title: "Couldn't delete Logs", reason: "You don't have permission.")
            let sut = FileBrowserView(screen: .directory(listing), folderSizes: [:], failure: failure, actions: FileBrowserActions())

            let row = try sut.inspect().find(DebugDrawerIssueRow<Text, EmptyView>.self)

            #expect(try row.actualView().title == failure.title)
            #expect(try row.actualView().severity == .error)
            #expect(try row.find(text: failure.reason).string() == failure.reason)
        }
    }
#endif
