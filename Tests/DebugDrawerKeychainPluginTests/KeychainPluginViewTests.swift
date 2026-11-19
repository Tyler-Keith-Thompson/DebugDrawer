// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import DebugDrawer
    @testable import DebugDrawerKeychainPlugin
    import Foundation
    import Security
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
            let sut = KeychainPluginView(
                transport: DebugDrawerPluginTransport(
                    initial: KeychainSnapshot(
                        contents: .items([item, KeychainFixtures.certificate]),
                        selection: KeychainOpenItem(item: item, value: .held)
                    ),
                    snapshots: AsyncStream { $0.finish() },
                    send: { sent.append($0.action) }
                ),
                revealedValue: { _ in Data("s3cr3t".utf8) }
            )
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

        @Test("The open form sends Save with what it holds, its password from the process, and Cancel, as commands")
        func formSendsCommands() throws {
            var sent: [KeychainCommand.Action] = []
            let draft = GenericPassword(service: "com.example.App", account: "ada", value: "s3cr3t", accessGroup: "TEAMID.com.example.app")
            let item = KeychainFixtures.password
            let sut = KeychainPluginView(
                transport: DebugDrawerPluginTransport(
                    initial: KeychainSnapshot(contents: .items([item]), editor: .editing(item, draft)),
                    snapshots: AsyncStream { $0.finish() },
                    send: { sent.append($0.action) }
                ),
                revealedValue: { $0 == item.id ? Data("s3cr3t".utf8) : nil }
            )
            let expected: [KeychainCommand.Action] = [.save(draft), .cancelEditing]

            let view = try sut.inspect()
            try view.find(button: "Save").tap()
            try view.find(button: "Cancel").tap()

            #expect(sent == expected)
            #expect(throws: Never.self) { try view.find(text: "Edit password") }
        }

        @Test("In the app's process the plugin's view shows the open item's password and starts the edit form from it, read from the model")
        func revealsInProcess() throws {
            let keychain = FakeKeychain()
            let ada = keychain.seed(
                .genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"], value: Data("s3cr3t".utf8)
            )
            let model = KeychainModel(keychain: keychain)
            let sut = KeychainPlugin(model: model)
            model.perform(KeychainCommand(.reload))
            model.perform(KeychainCommand(.toggle(ada)))

            let shown = try sut.body.inspect().find(text: "s3cr3t").string()
            model.perform(KeychainCommand(.startEditing(ada)))
            let form = try sut.body.inspect().find(KeychainPasswordForm.self).actualView()

            #expect(model.snapshot.selection?.value == .held)
            #expect(shown == "s3cr3t")
            #expect(form.editor.draft.value == "s3cr3t")
        }

        @Test("A view fed snapshots alone, as a viewer elsewhere is, has no password to show")
        func snapshotsAloneShowNoPassword() throws {
            let keychain = FakeKeychain()
            let ada = keychain.seed(
                .genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"], value: Data("s3cr3t".utf8)
            )
            let model = KeychainModel(keychain: keychain)
            model.perform(KeychainCommand(.reload))
            model.perform(KeychainCommand(.toggle(ada)))
            let received = try JSONDecoder().decode(KeychainSnapshot.self, from: JSONEncoder().encode(model.snapshot))
            let sut = KeychainPluginView(
                transport: DebugDrawerPluginTransport(initial: received, snapshots: AsyncStream { $0.finish() }, send: { _ in }),
                revealedValue: { _ in nil }
            )

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "<no data>") }
            #expect((try? view.find(text: "s3cr3t")) == nil)
        }
    }
#endif
