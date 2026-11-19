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
    struct FileItemMoreMenuViewTests {
        @Test("More offers Import…, Copy Path, Copy Text, Reveal in Finder, Rename… and Delete, and each calls its action once")
        func eachActionFires() throws {
            final class Calls {
                var imports = 0
                var pathCopies = 0
                var textCopies = 0
                var reveals = 0
                var renames = 0
                var deletes = 0
            }
            let calls = Calls()
            let sut = FileItemMoreMenu(
                name: "Exports",
                importFile: { calls.imports += 1 },
                copyPath: { calls.pathCopies += 1 },
                copyText: { calls.textCopies += 1 },
                revealInFinder: { calls.reveals += 1 },
                rename: { calls.renames += 1 },
                delete: { calls.deletes += 1 }
            )

            let menu = try sut.inspect().find(ViewType.Menu.self) { try $0.accessibilityLabel().string() == "More" }
            for title in ["Import…", "Copy Path", "Copy Text", "Reveal in Finder", "Rename…", "Delete"] {
                try menu.find(button: title).tap()
            }

            #expect(calls.imports == 1)
            #expect(calls.pathCopies == 1)
            #expect(calls.textCopies == 1)
            #expect(calls.reveals == 1)
            #expect(calls.renames == 1)
            #expect(calls.deletes == 1)
        }

        @Test("Delete in More is destructive, and each action keeps its accessibility label and hint")
        func accessibilityAndRole() throws {
            let sut = FileItemMoreMenu(
                name: "Exports", importFile: {}, copyPath: {}, copyText: {}, revealInFinder: {}, rename: {}, delete: {}
            )
            let titles = ["Import…", "Copy Path", "Copy Text", "Reveal in Finder", "Rename…", "Delete"]
            let expectedLabels = ["Import…", "Copy Path", "Copy Text", "Reveal in Finder", "Rename…", "Delete Exports"]
            let expectedHints = [
                "Copies a file you pick into this folder",
                "Copies to the clipboard",
                "Copies to the clipboard",
                "Shows the file in a Finder window",
                "Edits the name of Exports below",
                "Asks below before deleting"
            ]
            let expectedRole = ButtonRole.destructive

            let view = try sut.inspect()
            let buttons = try titles.map { try view.find(button: $0) }
            let labels = try buttons.map { try $0.accessibilityLabel().string() }
            let hints = try buttons.map { try $0.accessibilityHint().string() }
            let role = try view.find(button: "Delete").role()
            let more = try view.find(ViewType.Menu.self).accessibilityLabel().string()

            #expect(labels == expectedLabels)
            #expect(hints == expectedHints)
            #expect(role == expectedRole)
            #expect(more == "More")
        }

        @Test("Without its optional actions More offers Copy Path alone")
        func copyPathOnly() throws {
            let sut = FileItemMoreMenu(name: "Info.plist", copyPath: {})
            let expected = ["Copy Path"]

            let actual = try sut.inspect().findAll(ViewType.Button.self).map { try $0.labelView().text().string() }

            #expect(actual == expected)
        }

        @Test("While a rename or delete is open, Rename… and Delete are disabled")
        func disabledWhileAsking() throws {
            let sut = FileItemMoreMenu(name: "Exports", copyPath: {}, rename: {}, delete: {}, isAsking: true)

            let view = try sut.inspect()
            let renameDisabled = try view.find(button: "Rename…").isDisabled()
            let deleteDisabled = try view.find(button: "Delete").isDisabled()

            #expect(renameDisabled)
            #expect(deleteDisabled)
        }

        @Test("A folder's row shows Refresh and More, and hands Refresh and Import… their actions")
        func folderRowRoutesActions() throws {
            final class Calls {
                var refreshes = 0
                var imports = 0
            }
            let calls = Calls()
            let url = URL(filePath: "/data/Documents/Exports", directoryHint: .isDirectory)
            let folder = FileItem(url: url, isDirectory: true, size: 0, modified: nil, created: nil)
            let sut = FileItemActions(
                item: folder,
                canChange: true,
                canImport: true,
                actions: FileBrowserActions(refresh: { calls.refreshes += 1 }, importFile: { calls.imports += 1 })
            )

            let view = try sut.inspect()
            let refresh = try view.find(button: "Refresh")
            let refreshInMore = (try? refresh.find(FileItemMoreMenu.self, relation: .parent)) != nil
            let importInMore = (try? view.find(button: "Import…").find(FileItemMoreMenu.self, relation: .parent)) != nil
            try refresh.tap()
            try view.find(FileItemMoreMenu.self).find(button: "Import…").tap()

            #expect(!refreshInMore)
            #expect(importInMore)
            #expect(calls.refreshes == 1)
            #expect(calls.imports == 1)
        }
    }
#endif
