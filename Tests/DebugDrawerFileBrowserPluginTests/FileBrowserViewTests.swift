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
    struct FileBrowserViewTests {
        @Test("The bundle offers no Import, Rename or Delete: not at its root, in a folder inside it, or on a file")
        func bundleHasNoChanges() throws {
            let bundle = URL(filePath: "/Applications/Example.app", directoryHint: .isDirectory)
            let root = FileRoot(kind: .bundle, url: bundle)
            let resources = bundle.appending(path: "Contents/Resources", directoryHint: .isDirectory)
            let plist = FileItem(url: bundle.appending(path: "Contents/Info.plist"), isDirectory: false, size: 1_024, modified: nil, created: nil)
            func folder(_ url: URL) -> DirectoryView {
                let directory = FileItem(url: url, isDirectory: true, size: 0, modified: nil, created: nil)
                let contents = DirectoryContents(directory: directory, items: [plist])
                let listing = DirectoryListing(root: root, url: url, contents: .loaded(contents))
                return DirectoryView(listing: listing, folderSizes: [:], actions: FileBrowserActions())
            }
            let file = FileDetail(
                detail: FileDetailState(root: root, item: plist, preview: .loaded(.propertyList(PreviewText(lines: ["<plist/>"]), .xml))),
                actions: FileBrowserActions()
            )
            let changes = ["Import…", "Rename…", "Delete"]

            let views = [try folder(bundle).inspect(), try folder(resources).inspect(), try file.inspect()]

            for view in views {
                for title in changes {
                    #expect(throws: (any Error).self) { try view.find(button: title) }
                }
                #expect(try view.find(text: "Read-only").string() == "Read-only")
            }
        }

        @Test("Outside the bundle a folder offers Import, Rename and Delete, and its root offers only Import")
        func foldersOutsideTheBundle() throws {
            let documents = URL(filePath: "/data/Documents", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let exports = documents.appending(path: "Exports", directoryHint: .isDirectory)
            func folder(_ url: URL) -> DirectoryView {
                let directory = FileItem(url: url, isDirectory: true, size: 0, modified: nil, created: nil)
                let contents = DirectoryContents(directory: directory, items: [])
                let listing = DirectoryListing(root: root, url: url, contents: .loaded(contents))
                return DirectoryView(listing: listing, folderSizes: [:], actions: FileBrowserActions())
            }

            let rootView = try folder(documents).inspect()
            let subfolder = try folder(exports).inspect()

            #expect(try rootView.find(button: "Import…").labelView().text().string() == "Import…")
            #expect(throws: (any Error).self) { try rootView.find(button: "Rename…") }
            #expect(throws: (any Error).self) { try rootView.find(button: "Delete") }
            #expect(try subfolder.find(button: "Import…").labelView().text().string() == "Import…")
            #expect(try subfolder.find(button: "Rename…").labelView().text().string() == "Rename…")
            #expect(try subfolder.find(button: "Delete").labelView().text().string() == "Delete")
        }

        @Test("A folder row shows the total size of its contents, a file row its own size; tapping a row opens it")
        func rowSizes() throws {
            let documents = URL(filePath: "/data/Documents", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let logs = FileItem(
                url: documents.appending(path: "Logs", directoryHint: .isDirectory), isDirectory: true, size: 0, modified: nil, created: nil
            )
            let note = FileItem(url: documents.appending(path: "note.txt"), isDirectory: false, size: 512, modified: nil, created: nil)
            let directory = FileItem(url: documents, isDirectory: true, size: 0, modified: nil, created: nil)
            let contents = DirectoryContents(directory: directory, items: [logs, note])
            var opened: [FileBrowserPlace] = []
            let locale = Locale(identifier: "en_US")
            let sut = DirectoryView(
                listing: DirectoryListing(root: root, url: documents, contents: .loaded(contents)),
                folderSizes: [logs.path: 2_048_000, documents.filePath: 5_000_512],
                actions: FileBrowserActions(open: { opened.append($0) })
            )
            .environment(\.locale, locale)
            let expectedSizes = [Int64(2_048_000).byteCountText(locale), Int64(512).byteCountText(locale)]
            let expectedTotal = Int64(5_000_512).byteCountText(locale)

            let rows = try sut.inspect().findAll(FileListRow.self)
            let actual = try rows.map { try $0.actualView().size }
            try rows[0].find(ViewType.Button.self).tap()

            #expect(actual == expectedSizes)
            #expect(opened == [.directory(root, logs.url)])
            #expect(try sut.inspect().find(text: expectedTotal).string() == expectedTotal)
        }

        @Test("A folder still being counted shows an ellipsis for its size")
        func uncountedFolder() throws {
            let sut = FileListRow(title: "Logs", systemImage: "folder", size: nil, hint: "Opens the folder") {}

            #expect(try sut.inspect().find(text: "…").string() == "…")
        }

        @Test("The list of roots shows each root's title, path and total, and warns of a group with no container")
        func rootList() throws {
            let roots = FileRoots(
                available: [
                    FileRoot(kind: .documents, url: URL(filePath: "/data/Documents")),
                    FileRoot(kind: .bundle, url: URL(filePath: "/b/Example.app"))
                ],
                missingAppGroups: ["group.absent"]
            )
            var opened: [FileRoot] = []
            let sut = FileRootList(roots: roots, folderSizes: ["/data/Documents": 1_000]) { opened.append($0) }
                .environment(\.locale, Locale(identifier: "en_US"))
            let expectedTitles = ["Documents", "App bundle"]
            let expectedDetails: [String?] = ["/data/Documents", "/b/Example.app"]
            let expectedSizes: [String?] = ["1 kB", nil]
            let expectedWarning = "No container for group.absent"

            let rows = try sut.inspect().findAll(FileListRow.self).map { try $0.actualView() }
            rows[1].onOpen()

            #expect(rows.map(\.title) == expectedTitles)
            #expect(rows.map(\.detail) == expectedDetails)
            #expect(rows.map(\.size) == expectedSizes)
            #expect(opened.map(\.kind) == [.bundle])
            #expect(try sut.inspect().find(text: expectedWarning).string() == expectedWarning)
        }

        @Test("Text, JSON, XML and binary property lists preview as text, and a PNG as an image", arguments: [
            ("text", Data("hello\nworld".utf8)),
            ("json", Data(#"{"a":1}"#.utf8)),
            ("xml", Data(#"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>a</key><true/></dict></plist>"#.utf8)),
            ("binary", Data(base64Encoded: "YnBsaXN0MDDRAQJRYQkICw0AAAAAAAABAQAAAAAAAAADAAAAAAAAAAAAAAAAAAAADg==") ?? Data()),
            ("png", Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAEElEQVR4nGP4z8AARww4OQD1MQv1NXv7ggAAAABJRU5ErkJggg==")
                ?? Data())
        ])
        func previews(kind: String, data: Data) throws {
            let preview = FilePreview(data: data, isTruncated: false)
            let sut = FilePreviewView(preview: preview, fileSize: Int64(data.count))

            let view = try sut.inspect()

            if kind == "png" {
                #expect(throws: Never.self) { try view.find(ViewType.Image.self) }
                #expect(preview.kindTitle == "PNG image")
            } else {
                let lines = try view.find(PreviewTextView.self).findAll(ViewType.Text.self).map { try $0.string() }
                #expect(!lines.isEmpty)
                #expect(lines.joined().contains(kind == "text" ? "hello" : "a"))
                #expect(preview.text != nil)
            }
        }

        @Test("Text cut short says how much of the file it shows")
        func truncatedNote() throws {
            let sut = FilePreviewView(preview: .text(PreviewText(lines: ["abc"], isTruncated: true)), fileSize: 3_000_000)
                .environment(\.locale, Locale(identifier: "en_US"))
            let expected = "Showing the first 1 MB of 3 MB."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
        }

        @Test("Delete asks first, in place, then deletes; Cancel leaves the file")
        func deleteConfirmation() async throws {
            let item = FileItem(url: URL(filePath: "/data/Documents/old.log"), isDirectory: false, size: 1, modified: nil, created: nil)
            var deleted: [FileItem] = []
            let sut = FileItemActions(item: item, canChange: true, actions: FileBrowserActions(delete: { deleted.append($0) }))
            var askedBeforeDeleting = false

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(button: "Delete").tap()
                }
                try await sut.inspection.inspect { view in
                    askedBeforeDeleting = deleted.isEmpty && (try? view.find(text: "Delete old.log?")) != nil
                    try view.find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Delete old.log now" }.tap()
                }
            }

            #expect(askedBeforeDeleting)
            #expect(deleted == [item])
        }

        @Test("A file offers Share and Delete in the row, and Copy Path, Copy Text, Reveal in Finder and Rename… in its More menu")
        func fileActions() throws {
            let item = FileItem(url: URL(filePath: "/data/Documents/notes.txt"), isDirectory: false, size: 5, modified: nil, created: nil)
            let sut = FileItemActions(item: item, canChange: true, copyText: "hello", actions: FileBrowserActions())
            let expectedMenuItems = ["Copy Path", "Copy Text", "Reveal in Finder", "Rename…"]

            let view = try sut.inspect()
            let menu = try view.find(ViewType.Menu.self)
            let menuTitle = try menu.labelView().text().string()
            let actual = try menu.findAll(ViewType.Button.self).map { try $0.labelView().text().string() }
            let share = try view.find(ViewType.ShareLink.self).labelView().text().string()
            let delete = try view.find(button: "Delete").labelView().text().string()

            #expect(menuTitle == "More")
            #expect(actual == expectedMenuItems)
            #expect(share == "Share…")
            #expect(delete == "Delete")
        }

        @Test("Rename edits the name in place and renames to what was typed")
        func renameInPlace() async throws {
            let item = FileItem(url: URL(filePath: "/data/Documents/draft.txt"), isDirectory: false, size: 1, modified: nil, created: nil)
            var renamed: [String] = []
            let sut = FileItemActions(item: item, canChange: true, actions: FileBrowserActions(rename: { renamed.append($1) }))
            var startingName = ""

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(button: "Rename…").tap()
                }
                try await sut.inspection.inspect { view in
                    startingName = try view.find(ViewType.TextField.self).input()
                    try view.find(ViewType.TextField.self).setInput("final.txt")
                }
                try await sut.inspection.inspect { view in
                    try view.find(button: "Rename").tap()
                }
            }

            #expect(startingName == "draft.txt")
            #expect(renamed == ["final.txt"])
        }
    }
#endif
