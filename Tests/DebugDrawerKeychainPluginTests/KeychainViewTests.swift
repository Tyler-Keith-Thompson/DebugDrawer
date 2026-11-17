// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerKeychainPlugin
    import Foundation
    import Security
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct KeychainViewTests {
        @Test("A password's detail shows its accessibility, synchronizable and creation date among its attributes")
        func passwordDetailAttributes() throws {
            let selection = KeychainSelection(item: KeychainFixtures.password, value: .success(Data("s3cr3t-token".utf8)))
            let sut = KeychainItemDetail(selection: selection, redaction: .standard, onEdit: {}, onDelete: {})
            let expected = [
                "Service", "com.example.App", "Account", "ada@example.com", "Label", "API token", "Access group", "TEAMID.com.example.app",
                "Accessible", "AfterFirstUnlock", "Synchronizable", "No", "Created", "2026-05-09T06:13:20Z", "Modified", "2026-05-10T06:13:20Z"
            ]

            let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
            // ViewInspector finds a key-value row's value more than once, so repeats in a row are folded.
            let actual = texts.filter(expected.contains).reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }

            #expect(actual == expected)
        }

        @Test("Undocumented attributes sit under a collapsed Other attributes by raw key, apart from the named ones")
        func otherAttributes() throws {
            let selection = KeychainSelection(item: KeychainFixtures.password, value: .success(Data("s3cr3t".utf8)))
            let sut = KeychainItemDetail(selection: selection, redaction: .standard, onEdit: {}, onDelete: {})
            let expectedDigest = "dc59fec6723a07b9003ac3668721466fc47f25e1"

            let group = try sut.inspect().find(ViewType.DisclosureGroup.self)
            let label = try group.labelView().text().string()
            let isExpanded = try group.isExpanded()
            let inside = try group.findAll(ViewType.Text.self).map { try $0.string() }
            let outside = try sut.inspect()
                .findAll(ViewType.Text.self, where: { (try? $0.find(ViewType.DisclosureGroup.self, relation: .parent)) == nil })
                .map { try $0.string() }

            #expect(label == "Other attributes")
            #expect(!isExpanded)
            #expect(inside.contains("sha1"))
            #expect(inside.contains(expectedDigest))
            #expect(inside.contains("tomb"))
            #expect(!outside.contains("sha1"))
            #expect(!outside.contains("tomb"))
            #expect(outside.contains("Accessible"))
        }

        @Test("A detail with only documented attributes has no Other attributes")
        func noOtherAttributes() throws {
            let selection = KeychainSelection(item: KeychainFixtures.certificate, value: .success(nil))
            let sut = KeychainItemDetail(selection: selection, redaction: .standard, onDelete: {})

            let group = try? sut.inspect().find(ViewType.DisclosureGroup.self)

            #expect(group == nil)
        }

        @Test("A certificate's detail lists its attributes and Copy Attributes, with no value, Copy Value or Edit")
        func certificateDetail() throws {
            let selection = KeychainSelection(item: KeychainFixtures.certificate, value: .success(nil))
            let sut = KeychainItemDetail(selection: selection, redaction: .standard, onDelete: {})

            let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
            let copyAttributes = try? sut.inspect().find(button: "Copy Attributes")
            let copyValue = try? sut.inspect().find(button: "Copy Value")
            let edit = try? sut.inspect().find(button: "Edit…")

            #expect(texts.contains("Subject"))
            #expect(texts.contains("301a3118301606035504030c0f4578616d706c6520526f6f74204341"))
            #expect(texts.contains("Serial number"))
            #expect(!texts.contains("<no data>"))
            #expect(copyAttributes != nil)
            #expect(copyValue == nil)
            #expect(edit == nil)
        }

        @Test("A key's detail shows its class, type and size in words")
        func keyDetail() throws {
            let selection = KeychainSelection(item: KeychainFixtures.key, value: .success(nil))
            let sut = KeychainItemDetail(selection: selection, redaction: .standard, onDelete: {})

            let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(texts.contains("Private"))
            #expect(texts.contains("Elliptic curve"))
            #expect(texts.contains("256"))
        }

        @Test("Edit… in a generic password's detail opens the form on it")
        func editFromDetail() throws {
            var edits = 0
            let selection = KeychainSelection(item: KeychainFixtures.password, value: .success(Data("s3cr3t".utf8)))
            let sut = KeychainItemDetail(selection: selection, redaction: .standard, onEdit: { edits += 1 }, onDelete: {})

            try sut.inspect().find(button: "Edit…").tap()

            #expect(edits == 1)
        }

        @Test("The access group menu offers All and each group; choosing one sets the filter")
        func groupPicker() throws {
            var filter = KeychainFilter()
            let binding = Binding(get: { filter }, set: { filter = $0 })
            let sut = KeychainListView(
                items: [KeychainFixtures.password, KeychainFixtures.sharedPassword],
                accessGroups: ["TEAMID.com.example.app", "TEAMID.com.example.shared"],
                filter: binding, selection: nil, failure: nil, issue: nil, redaction: .standard, actions: KeychainListActions()
            )
            let expectedChoices = ["All", "TEAMID.com.example.app", "TEAMID.com.example.shared", "Access group"]

            let picker = try sut.inspect().find(ViewType.Picker.self)
            let choices = try picker.findAll(ViewType.Text.self).map { try $0.string() }
            try picker.select(value: String?.some("TEAMID.com.example.shared"))

            #expect(choices == expectedChoices)
            #expect(filter.accessGroup == "TEAMID.com.example.shared")
        }

        @Test("With no access groups known, the list shows no group menu; Add Password… and Reload call back")
        func listActions() throws {
            var calls: [String] = []
            var filter = KeychainFilter()
            let sut = KeychainListView(
                items: [], accessGroups: [], filter: Binding(get: { filter }, set: { filter = $0 }), selection: nil, failure: nil, issue: nil,
                redaction: .standard, actions: KeychainListActions(add: { calls.append("add") }, reload: { calls.append("reload") })
            )

            let picker = try? sut.inspect().find(ViewType.Picker.self)
            try sut.inspect().find(button: "Add Password…").tap()
            try sut.inspect().find(button: "Reload").tap()

            #expect(picker == nil)
            #expect(calls == ["add", "reload"])
        }

        @Test("A keychain that refuses to be read shows why")
        func unavailable() throws {
            var filter = KeychainFilter()
            let error = KeychainError(status: -34018)
            let sut = KeychainListView(
                items: [], accessGroups: [], filter: Binding(get: { filter }, set: { filter = $0 }), selection: nil, failure: error, issue: nil,
                redaction: .standard, actions: KeychainListActions()
            )

            let title = try sut.inspect().find(text: "Keychain unavailable").string()
            let message = try sut.inspect().find(text: error.message).string()

            #expect(title == "Keychain unavailable")
            #expect(message.hasSuffix("(-34018)"))
        }

        @Test("The form hides the password until Show password, then saves every field typed")
        func formRevealsAndSaves() async throws {
            var saved: [GenericPassword] = []
            let sut = KeychainPasswordForm(
                editor: .adding(GenericPassword()), accessGroups: ["TEAMID.com.example.app"], issue: nil,
                save: { saved.append($0) }, cancel: {}
            )
            var secureBefore = false
            var plainBefore = true
            var disabledBefore = false
            var plainAfter = false

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    secureBefore = (try? view.find(ViewType.SecureField.self)) != nil
                    plainBefore = (try? view.find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "Password" })) != nil
                    disabledBefore = try view.find(button: "Save").isDisabled()
                    try view.find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "Service" }).setInput("com.example.App")
                    try view.find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "Account" }).setInput("ada")
                    try view.find(ViewType.SecureField.self).setInput("s3cr3t")
                    try view.find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "Show password" }).tap()
                }
                try await sut.inspection.inspect { view in
                    plainAfter = (try? view.find(ViewType.TextField.self, where: { try $0.accessibilityLabel().string() == "Password" })) != nil
                    try view.find(button: "Save").tap()
                }
            }

            #expect(secureBefore)
            #expect(!plainBefore)
            #expect(disabledBefore)
            #expect(plainAfter)
            #expect(saved == [GenericPassword(service: "com.example.App", account: "ada", value: "s3cr3t")])
        }

        @Test("The edit form starts from the item, shows its group without a menu, and Cancel calls back")
        func editForm() throws {
            var cancels = 0
            let draft = GenericPassword(
                service: "com.example.App", account: "ada", value: "s3cr3t",
                accessGroup: "TEAMID.com.example.shared", accessibility: .afterFirstUnlock
            )
            let sut = KeychainPasswordForm(
                editor: .editing(KeychainFixtures.sharedPassword, draft), accessGroups: ["TEAMID.com.example.app", "TEAMID.com.example.shared"],
                issue: nil, save: { _ in }, cancel: { cancels += 1 }
            )

            let title = try sut.inspect().find(text: "Edit password").string()
            let group = try sut.inspect().find(text: "TEAMID.com.example.shared").string()
            let pickers = try sut.inspect().findAll(ViewType.Picker.self).map { try $0.accessibilityLabel().string() }
            try sut.inspect().find(button: "Cancel").tap()

            #expect(title == "Edit password")
            #expect(group == "TEAMID.com.example.shared")
            #expect(pickers == ["Accessible"])
            #expect(cancels == 1)
        }

        @Test("The header counts the items once the keychain is read")
        func headerCount() throws {
            let keychain = FakeKeychain()
            keychain.seed(.certificate, [kSecAttrLabel as String: "Example Root CA"])
            keychain.seed(.key, [kSecAttrLabel as String: "Signing"])
            let model = KeychainModel(keychain: keychain)
            let before = try? KeychainHeaderAccessory(model: model).inspect().find(ViewType.Text.self)

            model.reload()
            let actual = try KeychainHeaderAccessory(model: model).inspect().find(ViewType.Text.self).string()

            #expect(before == nil)
            #expect(actual == "2 items")
        }
    }
#endif
