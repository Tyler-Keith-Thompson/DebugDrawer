// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import DebugDrawer
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FileBrowserPluginViewTests {
        @Test("The view starts reading as it appears, sends Back, Refresh and a row's open as commands, and stops reading as it goes")
        func sendsCommands() throws {
            let documents = URL(filePath: "/data/Documents", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let note = FileItem(url: documents.appending(path: "note.txt"), isDirectory: false, size: 5, modified: nil, created: nil)
            let directory = FileItem(url: documents, isDirectory: true, size: 0, modified: nil, created: nil)
            let listing = DirectoryListing(root: root, url: documents, contents: .loaded(DirectoryContents(directory: directory, items: [note])))
            var sent: [FileBrowserCommand.Action] = []
            let sut = FileBrowserPluginView(transport: DebugDrawerPluginTransport(
                initial: FileBrowserSnapshot(screen: .directory(listing)), snapshots: AsyncStream { $0.finish() }, send: { sent.append($0.action) }
            ))
            let expected: [FileBrowserCommand.Action] = [.startReading, .back, .refresh, .open(.file(root, note)), .stopReading]

            let view = try sut.inspect()
            try view.find(FileBrowserView.self).callOnAppear()
            try view.find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "Back to Locations" }).tap()
            try view.find(button: "Refresh").tap()
            try view.find(FileListRow.self).find(ViewType.Button.self).tap()
            try view.find(FileBrowserView.self).callOnDisappear()

            #expect(sent == expected)
        }

        @Test("The header shows the root of the place shown, and nothing at the list of roots")
        func headerAccessory() throws {
            let documents = URL(filePath: "/data/Documents", directoryHint: .isDirectory)
            let root = FileRoot(kind: .documents, url: documents)
            let listing = DirectoryListing(root: root, url: documents, contents: .loading)
            let atFolder = FileBrowserHeaderAccessory(transport: DebugDrawerPluginTransport(
                initial: FileBrowserSnapshot(screen: .directory(listing)), snapshots: AsyncStream { $0.finish() }, send: { _ in }
            ))
            let atRoots = FileBrowserHeaderAccessory(transport: DebugDrawerPluginTransport(
                initial: FileBrowserSnapshot(screen: .roots(FileRoots(available: [root]), isEmpty: false)),
                snapshots: AsyncStream { $0.finish() },
                send: { _ in }
            ))

            let actual = try atFolder.inspect().find(ViewType.Text.self).string()

            #expect(actual == "Documents")
            #expect(throws: (any Error).self) { try atRoots.inspect().find(ViewType.Text.self) }
        }
    }
#endif
