// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import DebugDrawer
    @testable import DebugDrawerKeychainPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct KeychainPluginViewTests {
        @Test("The list draws the snapshot, and sends typing, choosing an item, Edit…, Add Password… and Reload as commands")
        func listSendsCommands() throws {
            var sent: [KeychainCommand.Action] = []
            let item = KeychainFixtures.password
            let sut = KeychainPluginView(transport: DebugDrawerPluginTransport(
                initial: KeychainSnapshot(
                    contents: .items([item, KeychainFixtures.certificate]),
                    selection: KeychainSelection(item: item, value: .success(Data("s3cr3t".utf8)))
                ),
                snapshots: AsyncStream { $0.finish() },
                send: { sent.append($0.action) }
            ))
            let expected: [KeychainCommand.Action] = [
                .setFilter(KeychainFilter(text: "ada")),
                .toggle(item.id),
                .startEditing(item.id),
                .startAdding,
                .reload
            ]

            let view = try sut.inspect()
            try view.find(ViewType.TextField.self).setInput("ada")
            try view.find(button: "ada@example.com").tap()
            try view.find(button: "Edit…").tap()
            try view.find(button: "Add Password…").tap()
            try view.find(button: "Reload").tap()

            #expect(sent == expected)
            #expect(throws: Never.self) { try view.find(text: "Example Root CA") }
        }

        @Test("The open form sends Save with what it holds, and Cancel, as commands")
        func formSendsCommands() throws {
            var sent: [KeychainCommand.Action] = []
            let draft = GenericPassword(service: "com.example.App", account: "ada", value: "s3cr3t", accessGroup: "TEAMID.com.example.app")
            let sut = KeychainPluginView(transport: DebugDrawerPluginTransport(
                initial: KeychainSnapshot(contents: .items([KeychainFixtures.password]), editor: .editing(KeychainFixtures.password, draft)),
                snapshots: AsyncStream { $0.finish() },
                send: { sent.append($0.action) }
            ))
            let expected: [KeychainCommand.Action] = [.save(draft), .cancelEditing]

            let view = try sut.inspect()
            try view.find(button: "Save").tap()
            try view.find(button: "Cancel").tap()

            #expect(sent == expected)
            #expect(throws: Never.self) { try view.find(text: "Edit password") }
        }
    }
#endif
