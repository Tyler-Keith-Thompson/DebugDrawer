#if DEBUG
    @testable import DebugDrawerKeychainPlugin
    import Foundation
    import Security
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct KeychainModelTests {
        @Test("Filtering by an access group lists that group's items alone; All lists both groups'")
        func filterByAccessGroup() {
            let keychain = FakeKeychain()
            keychain.seed(.genericPassword, [
                kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada",
                kSecAttrAccessGroup as String: "TEAMID.com.example.app"
            ])
            keychain.seed(.genericPassword, [
                kSecAttrService as String: "com.example.shared", kSecAttrAccount as String: "grace",
                kSecAttrAccessGroup as String: "TEAMID.com.example.shared"
            ])
            let sut = KeychainModel(keychain: keychain)
            sut.reload()

            sut.filter.accessGroup = "TEAMID.com.example.shared"
            let actual = sut.shownItems.map(\.account)
            sut.filter.accessGroup = nil
            let all = sut.shownItems.map(\.account)

            #expect(sut.accessGroups == ["TEAMID.com.example.app", "TEAMID.com.example.shared"])
            #expect(actual == ["grace"])
            #expect(all == ["ada", "grace"])
        }

        @Test("The text filter matches an item's account, service or label, ignoring case, within the chosen group")
        func filterByText() {
            let keychain = FakeKeychain()
            keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"])
            keychain.seed(.genericPassword, [
                kSecAttrService as String: "com.example.Other", kSecAttrAccount as String: "bob", kSecAttrLabel as String: "Refresh Token"
            ])
            keychain.seed(.genericPassword, [
                kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "carol",
                kSecAttrAccessGroup as String: "TEAMID.com.example.shared"
            ])
            let sut = KeychainModel(keychain: keychain)
            sut.reload()

            sut.filter.text = "TOKEN"
            let byLabel = sut.shownItems.map(\.account)
            sut.filter.text = "example.app"
            let byService = sut.shownItems.map(\.account)
            sut.filter.accessGroup = "TEAMID.com.example.shared"
            let byServiceInGroup = sut.shownItems.map(\.account)

            #expect(byLabel == ["bob"])
            #expect(byService == ["ada", "carol"])
            #expect(byServiceInGroup == ["carol"])
        }

        @Test("A generic password added through the form is listed, in the default group, and its value reads back")
        func addPassword() throws {
            let keychain = FakeKeychain()
            let sut = KeychainModel(keychain: keychain)
            sut.reload()
            sut.startAdding()
            let password = GenericPassword(
                service: "com.example.App", account: "ada", label: "Token", value: "s3cr3t", accessibility: .afterFirstUnlock
            )

            sut.save(password)
            let added = try #require(sut.shownItems.first)
            let actual = try keychain.value(of: added)

            #expect(sut.editor == nil)
            #expect(added.service == "com.example.App")
            #expect(added.account == "ada")
            #expect(added.label == "Token")
            #expect(added.accessGroup == "TEAMID.com.example.app")
            #expect(added.accessibility == .afterFirstUnlock)
            #expect(actual == Data("s3cr3t".utf8))
        }

        @Test("Adding while the filter shows a group starts the form in that group")
        func addInFilteredGroup() {
            let sut = KeychainModel(keychain: FakeKeychain())
            sut.filter.accessGroup = "TEAMID.com.example.shared"

            sut.startAdding()

            #expect(sut.editor == .adding(GenericPassword(accessGroup: "TEAMID.com.example.shared")))
        }

        @Test("Editing starts from the item's values and password, and saving rewrites that item alone, in its group")
        func editPassword() throws {
            let keychain = FakeKeychain()
            let reference = keychain.seed(.genericPassword, [
                kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada",
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked as String,
                kSecAttrAccessGroup as String: "TEAMID.com.example.shared"
            ], value: Data("old".utf8))
            keychain.seed(
                .genericPassword, [kSecAttrService as String: "com.example.Other", kSecAttrAccount as String: "ada"], value: Data("other".utf8)
            )
            let sut = KeychainModel(keychain: keychain)
            sut.reload()
            let item = try #require(sut.shownItems.first { $0.persistentReference == reference })
            sut.startEditing(item)
            var draft = try #require(sut.editor?.draft)
            draft.value = "new"
            draft.account = "ada.lovelace"

            sut.save(draft)
            let edited = try #require(sut.shownItems.first { $0.persistentReference == reference })
            let other = try #require(sut.shownItems.first { $0.persistentReference != reference })

            #expect(sut.editor == nil)
            #expect(edited.account == "ada.lovelace")
            #expect(edited.accessGroup == "TEAMID.com.example.shared")
            #expect(try keychain.value(of: edited) == Data("new".utf8))
            #expect(try keychain.value(of: other) == Data("other".utf8))
        }

        @Test("The edit form starts from the item's service, account, label, password, group and accessibility")
        func editDraft() throws {
            let keychain = FakeKeychain()
            keychain.seed(.genericPassword, [
                kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada", kSecAttrLabel as String: "Token",
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
                kSecAttrAccessGroup as String: "TEAMID.com.example.shared"
            ], value: Data("old".utf8))
            let sut = KeychainModel(keychain: keychain)
            sut.reload()
            let item = try #require(sut.shownItems.first)
            let expected = GenericPassword(
                service: "com.example.App", account: "ada", label: "Token", value: "old",
                accessGroup: "TEAMID.com.example.shared", accessibility: .afterFirstUnlockThisDeviceOnly
            )

            sut.startEditing(item)

            #expect(sut.editor == .editing(item, expected))
        }

        @Test("Editing a password that can't be read opens no form, so an empty one can't overwrite it, and reports why")
        func editUnreadable() throws {
            let keychain = FakeKeychain()
            keychain.seed(
                .genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"], value: Data("s3cr3t".utf8)
            )
            let sut = KeychainModel(keychain: keychain)
            sut.reload()
            let item = try #require(sut.shownItems.first)
            keychain.refusal = KeychainError(status: errSecInteractionNotAllowed)

            sut.startEditing(item)

            #expect(sut.editor == nil)
            #expect(sut.issue == KeychainIssue(action: "Couldn't read the password", error: KeychainError(status: errSecInteractionNotAllowed)))
        }

        @Test("A save the keychain refuses keeps the form open and reports why")
        func duplicateAdd() {
            let keychain = FakeKeychain()
            keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"])
            let sut = KeychainModel(keychain: keychain)
            sut.reload()
            sut.startAdding()

            sut.save(GenericPassword(service: "com.example.App", account: "ada", value: "x"))

            #expect(sut.editor != nil)
            #expect(sut.issue == KeychainIssue(action: "Couldn't save", error: KeychainError(status: errSecDuplicateItem)))
            #expect(sut.shownItems.count == 1)
        }

        @Test("Delete removes the item asked for and leaves another with the same account and service in another group")
        func deleteOne() throws {
            let keychain = FakeKeychain()
            let kept = keychain.seed(.genericPassword, [
                kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada",
                kSecAttrAccessGroup as String: "TEAMID.com.example.shared"
            ])
            keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"])
            let sut = KeychainModel(keychain: keychain)
            sut.reload()
            let doomed = try #require(sut.shownItems.first { $0.persistentReference != kept })
            sut.toggle(doomed)

            sut.delete(doomed)

            #expect(sut.shownItems.map(\.persistentReference) == [kept])
            #expect(sut.selection == nil)
        }

        @Test("A delete the keychain refuses reports why")
        func refusedDelete() throws {
            let keychain = FakeKeychain()
            keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"])
            let sut = KeychainModel(keychain: keychain)
            sut.reload()
            let item = try #require(sut.shownItems.first)
            keychain.refusal = KeychainError(status: errSecInteractionNotAllowed)
            let expected = KeychainIssue(action: "Couldn't delete", error: KeychainError(status: errSecInteractionNotAllowed))

            sut.delete(item)

            #expect(sut.issue == expected)
        }

        @Test("Opening an item reads its password; opening it again closes it")
        func toggleReadsValue() throws {
            let keychain = FakeKeychain()
            keychain.seed(
                .genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"], value: Data("s3cr3t".utf8)
            )
            let sut = KeychainModel(keychain: keychain)
            sut.reload()
            let item = try #require(sut.shownItems.first)

            sut.toggle(item)
            let opened = sut.selection
            sut.toggle(item)

            #expect(opened == KeychainSelection(item: item, value: .success(Data("s3cr3t".utf8))))
            #expect(sut.selection == nil)
        }

        @Test("Nothing is read until the list is first shown, and listing reads no item's value")
        func listingReadsNoValue() {
            let keychain = FakeKeychain()
            keychain.seed(
                .genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"], value: Data("s3cr3t".utf8)
            )
            let sut = KeychainModel(keychain: keychain)
            let before = sut.contents

            sut.reload()

            #expect(before == .unread)
            #expect(sut.shownItems.count == 1)
            #expect(keychain.valueReads.isEmpty)
        }

        @Test("Certificates and keys are listed after the passwords, with their attributes")
        func certificatesAndKeys() {
            let keychain = FakeKeychain()
            keychain.seed(.key, [
                kSecAttrApplicationTag as String: Data("com.example.signing".utf8), kSecAttrKeySizeInBits as String: NSNumber(value: 256)
            ])
            keychain.seed(.certificate, [kSecAttrLabel as String: "Example Root CA"])
            keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"])
            let sut = KeychainModel(keychain: keychain)

            sut.reload()
            let actual = sut.shownItems.map { "\($0.itemClass.title): \($0.title)" }
            let keySize = sut.shownItems.last?.attributes.first { $0.name == "Key size" }?.value

            #expect(actual == ["Password: ada", "Certificate: Example Root CA", "Key: com.example.signing"])
            #expect(keySize == "256")
        }

        @Test("A keychain that refuses to be read is reported, with no items")
        func unavailable() {
            let keychain = FakeKeychain()
            keychain.refusal = KeychainError(status: errSecMissingEntitlement)
            let sut = KeychainModel(keychain: keychain)

            sut.reload()

            #expect(sut.contents == .unavailable(KeychainError(status: errSecMissingEntitlement)))
            #expect(sut.shownItems.isEmpty)
        }

        @Test("Cancel closes the form and changes nothing")
        func cancel() {
            let keychain = FakeKeychain()
            let sut = KeychainModel(keychain: keychain)
            sut.startAdding()

            sut.cancelEditing()

            #expect(sut.editor == nil)
            #expect(keychain.records.isEmpty)
        }
    }
#endif
