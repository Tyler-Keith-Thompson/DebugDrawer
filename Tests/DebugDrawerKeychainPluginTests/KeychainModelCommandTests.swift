#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerKeychainPlugin
    import Foundation
    import Security
    import Testing

    // The model is read and driven here as an out-of-process reader would: through its snapshot,
    // encoded and decoded, and commands, sent through a direct transport, with no view. The keychain
    // is the hand-written in-memory FakeKeychain; nothing here reaches the real one. Every command
    // lands before `send(_:)` returns, so no test waits.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct KeychainModelCommandTests {
        @Test("A snapshot with items, a filter, an open password, a form and a refusal encodes to JSON and decodes equal")
        func snapshotRoundTrips() throws {
            let keychain = FakeKeychain()
            let reference = keychain.seed(.genericPassword, [
                kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada", kSecAttrLabel as String: "Token",
                kSecAttrCreationDate as String: Date(timeIntervalSinceReferenceDate: 800_000_000),
                kSecAttrModificationDate as String: Date(timeIntervalSinceReferenceDate: 800_086_400)
            ], value: Data("s3cr3t".utf8))
            keychain.seed(.key, [kSecAttrApplicationTag as String: Data("com.example.signing".utf8)])
            let sut = DebugDrawerPluginTransport.direct(to: KeychainModel(keychain: keychain))
            sut.send(KeychainCommand(.reload))
            sut.send(KeychainCommand(.setFilter(KeychainFilter(text: "ada", accessGroup: "TEAMID.com.example.app"))))
            sut.send(KeychainCommand(.toggle(reference)))
            sut.send(KeychainCommand(.startAdding))
            sut.send(KeychainCommand(.save(GenericPassword(service: "com.example.App", account: "ada"))))
            let expected = sut.snapshot

            let encoded = try JSONEncoder().encode(expected)
            let actual = try JSONDecoder().decode(KeychainSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.allItems.count == 2)
            #expect(actual.shownItems.map(\.account) == ["ada"])
            #expect(actual.shownItems.first?.service == "com.example.App")
            #expect(actual.shownItems.first?.label == "Token")
            #expect(actual.shownItems.first?.accessGroup == "TEAMID.com.example.app")
            #expect(actual.shownItems.first?.created == Date(timeIntervalSinceReferenceDate: 800_000_000))
            #expect(actual.shownItems.first?.modified == Date(timeIntervalSinceReferenceDate: 800_086_400))
            #expect(actual.selection?.value == .success(Data("s3cr3t".utf8)))
            #expect(actual.editor == .adding(GenericPassword(accessGroup: "TEAMID.com.example.app")))
            #expect(actual.issue == KeychainIssue(action: "Couldn't save", error: KeychainError(status: errSecDuplicateItem)))
        }

        @Test("A snapshot before reading, one of a keychain that refuses, and an unreadable password each round-trip through JSON")
        func otherSnapshotsRoundTrip() throws {
            let unread = KeychainModel(keychain: FakeKeychain()).snapshot
            let refusing = FakeKeychain()
            refusing.refusal = KeychainError(status: errSecMissingEntitlement)
            let unavailable = KeychainModel(keychain: refusing)
            unavailable.perform(KeychainCommand(.reload))
            let unreadable = KeychainSnapshot(
                contents: .items([KeychainFixtures.password]),
                selection: KeychainSelection(item: KeychainFixtures.password, value: .failure(KeychainError(status: errSecInteractionNotAllowed)))
            )
            let noValue = KeychainSnapshot(selection: KeychainSelection(item: KeychainFixtures.certificate, value: .success(nil)))
            let expected = [unread, unavailable.snapshot, unreadable, noValue]

            let actual = try expected.map { try JSONDecoder().decode(KeychainSnapshot.self, from: JSONEncoder().encode($0)) }

            #expect(actual == expected)
            #expect(unread.contents == .unread)
            #expect(unavailable.snapshot.contents == .unavailable(KeychainError(status: errSecMissingEntitlement)))
        }

        @Test("Every command, encoded to JSON and decoded, drives the model through a direct transport")
        func commandsRoundTrip() throws {
            let keychain = FakeKeychain()
            let ada = keychain.seed(
                .genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"], value: Data("old".utf8)
            )
            let bob = keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "bob"])
            let carol = keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.Other", kSecAttrAccount as String: "carol"])
            let sut = DebugDrawerPluginTransport.direct(to: KeychainModel(keychain: keychain))
            let edited = GenericPassword(service: "com.example.App", account: "ada", value: "new", accessGroup: "TEAMID.com.example.app")
            let commands: [KeychainCommand.Action] = [
                .reload,
                .toggle(ada),
                .startAdding,
                .cancelEditing,
                .startEditing(ada),
                .save(edited),
                .delete(bob),
                .setFilter(KeychainFilter(text: "other")),
                .deleteShown
            ]
            let expectedCalls: [FakeKeychain.Call] = [
                .items, .value(ada), .value(ada), .update(ada, edited), .items, .value(ada), .delete(bob), .items, .value(ada), .delete(carol),
                .items, .value(ada)
            ]

            for action in commands {
                let decoded = try JSONDecoder().decode(KeychainCommand.self, from: JSONEncoder().encode(KeychainCommand(action)))
                #expect(decoded.action == action)
                sut.send(decoded)
            }

            #expect(keychain.calls == expectedCalls)
            #expect(keychain.records.map(\.reference) == [ada])
            #expect(keychain.records.first?.value == Data("new".utf8))
            #expect(sut.snapshot.filter.text == "other")
            #expect(sut.snapshot.selection?.item.id == ada)
            #expect(sut.snapshot.editor == nil)
            #expect(sut.snapshot.issue == nil)
        }

        @Test("Listing puts passwords, internet passwords, certificates and keys in that order, each class in the keychain's own order")
        func listingInClassOrder() {
            let keychain = FakeKeychain()
            keychain.listsInStoredOrder = true
            keychain.seed(.key, [kSecAttrLabel as String: "Signing"])
            keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "zoe"])
            keychain.seed(.certificate, [kSecAttrLabel as String: "Example Root CA"])
            keychain.seed(.internetPassword, [kSecAttrServer as String: "example.com", kSecAttrAccount as String: "web"])
            keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"])
            let sut = DebugDrawerPluginTransport.direct(to: KeychainModel(keychain: keychain))
            let expected = ["Password: zoe", "Password: ada", "Internet: web", "Certificate: Example Root CA", "Key: Signing"]

            sut.send(KeychainCommand(.reload))
            let actual = sut.snapshot.shownItems.map { "\($0.itemClass.title): \($0.title)" }

            #expect(actual == expected)
            #expect(keychain.valueReads.isEmpty)
        }

        @Test("The filter sent shows the items of its group whose account, service or label holds its text, ignoring case")
        func filtering() {
            let keychain = FakeKeychain()
            keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"])
            keychain.seed(.genericPassword, [
                kSecAttrService as String: "com.example.Other", kSecAttrAccount as String: "bob", kSecAttrLabel as String: "Refresh Token"
            ])
            keychain.seed(.genericPassword, [
                kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "carol",
                kSecAttrAccessGroup as String: "TEAMID.com.example.shared"
            ])
            let sut = DebugDrawerPluginTransport.direct(to: KeychainModel(keychain: keychain))
            sut.send(KeychainCommand(.reload))

            sut.send(KeychainCommand(.setFilter(KeychainFilter(text: "TOKEN"))))
            let byLabel = sut.snapshot.shownItems.map(\.account)
            sut.send(KeychainCommand(.setFilter(KeychainFilter(text: "example.app"))))
            let byService = sut.snapshot.shownItems.map(\.account)
            sut.send(KeychainCommand(.setFilter(KeychainFilter(text: "example.app", accessGroup: "TEAMID.com.example.shared"))))
            let inGroup = sut.snapshot.shownItems.map(\.account)
            sut.send(KeychainCommand(.setFilter(KeychainFilter())))
            let all = sut.snapshot.shownItems.map(\.account)

            #expect(byLabel == ["bob"])
            #expect(byService == ["ada", "carol"])
            #expect(inGroup == ["carol"])
            #expect(all == ["ada", "bob", "carol"])
            #expect(sut.snapshot.accessGroups == ["TEAMID.com.example.app", "TEAMID.com.example.shared"])
        }

        @Test("Toggling an item reveals its password as Data, a refused read as the refusal, and toggling again closes it")
        func reveal() throws {
            let keychain = FakeKeychain()
            let ada = keychain.seed(
                .genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"], value: Data("s3cr3t".utf8)
            )
            let bob = keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "bob"])
            let sut = DebugDrawerPluginTransport.direct(to: KeychainModel(keychain: keychain))
            sut.send(KeychainCommand(.reload))
            let readsBeforeOpening = keychain.valueReads

            sut.send(KeychainCommand(.toggle(ada)))
            let revealed = sut.snapshot.selection
            sut.send(KeychainCommand(.toggle(ada)))
            let closed = sut.snapshot.selection
            keychain.refusal = KeychainError(status: errSecInteractionNotAllowed)
            sut.send(KeychainCommand(.toggle(bob)))
            let refused = sut.snapshot.selection

            #expect(readsBeforeOpening.isEmpty)
            #expect(revealed?.item.id == ada)
            #expect(revealed?.value == .success(Data("s3cr3t".utf8)))
            #expect(closed == nil)
            #expect(refused?.item.id == bob)
            #expect(refused?.value == .failure(KeychainError(status: errSecInteractionNotAllowed)))
        }

        @Test("A command naming an item that isn't listed does nothing")
        func unlistedItem() {
            let keychain = FakeKeychain()
            let ada = keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"])
            let sut = DebugDrawerPluginTransport.direct(to: KeychainModel(keychain: keychain))

            sut.send(KeychainCommand(.toggle(ada)))
            sut.send(KeychainCommand(.startEditing(ada)))
            sut.send(KeychainCommand(.delete(ada)))

            #expect(keychain.calls.isEmpty)
            #expect(keychain.records.count == 1)
            #expect(sut.snapshot.selection == nil)
            #expect(sut.snapshot.editor == nil)
        }

        @Test("Editing starts the form from the item and its password, and saving rewrites that item, closes the form and lists the change")
        func edit() throws {
            let keychain = FakeKeychain()
            let ada = keychain.seed(.genericPassword, [
                kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada", kSecAttrLabel as String: "Token",
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock as String
            ], value: Data("old".utf8))
            let sut = DebugDrawerPluginTransport.direct(to: KeychainModel(keychain: keychain))
            sut.send(KeychainCommand(.reload))
            let expectedDraft = GenericPassword(
                service: "com.example.App", account: "ada", label: "Token", value: "old",
                accessGroup: "TEAMID.com.example.app", accessibility: .afterFirstUnlock
            )

            sut.send(KeychainCommand(.startEditing(ada)))
            let draft = sut.snapshot.editor?.draft
            var changed = try #require(draft)
            changed.account = "ada.lovelace"
            changed.value = "new"
            sut.send(KeychainCommand(.save(changed)))
            let edited = sut.snapshot.allItems.first { $0.id == ada }

            #expect(draft == expectedDraft)
            #expect(sut.snapshot.editor == nil)
            #expect(edited?.account == "ada.lovelace")
            #expect(keychain.records.first?.value == Data("new".utf8))
        }

        @Test("An edit the keychain refuses to save keeps the form open with the refusal; one it can't read opens no form")
        func refusedEdit() throws {
            let keychain = FakeKeychain()
            let ada = keychain.seed(
                .genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"], value: Data("old".utf8)
            )
            let sut = DebugDrawerPluginTransport.direct(to: KeychainModel(keychain: keychain))
            sut.send(KeychainCommand(.reload))
            sut.send(KeychainCommand(.startEditing(ada)))
            let draft = try #require(sut.snapshot.editor?.draft)
            keychain.refusal = KeychainError(status: errSecInteractionNotAllowed)

            sut.send(KeychainCommand(.save(draft)))
            let saveRefused = sut.snapshot
            sut.send(KeychainCommand(.cancelEditing))
            sut.send(KeychainCommand(.startEditing(ada)))

            #expect(saveRefused.editor != nil)
            #expect(saveRefused.issue == KeychainIssue(action: "Couldn't save", error: KeychainError(status: errSecInteractionNotAllowed)))
            #expect(sut.snapshot.editor == nil)
            let expectedReadIssue = KeychainIssue(action: "Couldn't read the password", error: KeychainError(status: errSecInteractionNotAllowed))
            #expect(sut.snapshot.issue == expectedReadIssue)
        }

        @Test("Delete removes the item alone and closes its detail; a refused delete keeps it and says why")
        func deleteOne() {
            let keychain = FakeKeychain()
            let ada = keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"])
            let bob = keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "bob"])
            keychain.deleteRefusals[bob] = KeychainError(status: errSecInteractionNotAllowed)
            let sut = DebugDrawerPluginTransport.direct(to: KeychainModel(keychain: keychain))
            sut.send(KeychainCommand(.reload))
            sut.send(KeychainCommand(.toggle(ada)))

            sut.send(KeychainCommand(.delete(ada)))
            let afterDelete = sut.snapshot
            sut.send(KeychainCommand(.delete(bob)))

            #expect(afterDelete.allItems.map(\.id) == [bob])
            #expect(afterDelete.selection == nil)
            #expect(afterDelete.issue == nil)
            #expect(sut.snapshot.allItems.map(\.id) == [bob])
            #expect(sut.snapshot.issue == KeychainIssue(action: "Couldn't delete", error: KeychainError(status: errSecInteractionNotAllowed)))
        }

        @Test("Delete all deletes every item the filter shows, each alone, and leaves the rest")
        func deleteShown() {
            let keychain = FakeKeychain()
            let ada = keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"])
            let bob = keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "bob"])
            let other = keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.Other", kSecAttrAccount as String: "carol"])
            let sut = DebugDrawerPluginTransport.direct(to: KeychainModel(keychain: keychain))
            sut.send(KeychainCommand(.reload))
            sut.send(KeychainCommand(.toggle(bob)))
            sut.send(KeychainCommand(.setFilter(KeychainFilter(text: "example.app"))))

            sut.send(KeychainCommand(.deleteShown))

            #expect(keychain.calls.filter { if case .delete = $0 { true } else { false } } == [.delete(ada), .delete(bob)])
            #expect(keychain.records.map(\.reference) == [other])
            #expect(sut.snapshot.shownItems.isEmpty)
            #expect(sut.snapshot.allItems.map(\.id) == [other])
            #expect(sut.snapshot.selection == nil)
            #expect(sut.snapshot.issue == nil)
        }

        @Test("Delete all carries on past a refusal, keeps the refused item listed and reports the refusal")
        func deleteShownRefused() {
            let keychain = FakeKeychain()
            let ada = keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"])
            let bob = keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "bob"])
            let carol = keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "carol"])
            keychain.deleteRefusals[ada] = KeychainError(status: errSecInteractionNotAllowed)
            let sut = DebugDrawerPluginTransport.direct(to: KeychainModel(keychain: keychain))
            sut.send(KeychainCommand(.reload))

            sut.send(KeychainCommand(.deleteShown))

            #expect(keychain.calls.filter { if case .delete = $0 { true } else { false } } == [.delete(ada), .delete(bob), .delete(carol)])
            #expect(sut.snapshot.allItems.map(\.id) == [ada])
            #expect(sut.snapshot.issue == KeychainIssue(action: "Couldn't delete", error: KeychainError(status: errSecInteractionNotAllowed)))
        }

        @Test("Refresh reads the keychain again, so an item another part of the app added since is listed, and the open item stays open")
        func refreshPicksUpOutsideChange() {
            let keychain = FakeKeychain()
            let ada = keychain.seed(
                .genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"], value: Data("s3cr3t".utf8)
            )
            let sut = DebugDrawerPluginTransport.direct(to: KeychainModel(keychain: keychain))
            sut.send(KeychainCommand(.reload))
            sut.send(KeychainCommand(.toggle(ada)))
            let before = sut.snapshot.allItems.map(\.account)
            keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "bob"])

            let unchanged = sut.snapshot.allItems.map(\.account)
            sut.send(KeychainCommand(.reload))

            #expect(before == ["ada"])
            #expect(unchanged == ["ada"])
            #expect(sut.snapshot.allItems.map(\.account) == ["ada", "bob"])
            #expect(sut.snapshot.selection?.item.id == ada)
        }

        @Test("Commands land in the order sent: each reaches the keychain before the next, and the last filter sent is the one shown")
        func commandsInOrder() {
            let keychain = FakeKeychain()
            let ada = keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"])
            let sut = DebugDrawerPluginTransport.direct(to: KeychainModel(keychain: keychain))
            let added = GenericPassword(service: "com.example.App", account: "bob", value: "x")
            let typed = ["b", "bo", "bob"]

            sut.send(KeychainCommand(.reload))
            sut.send(KeychainCommand(.startAdding))
            sut.send(KeychainCommand(.save(added)))
            sut.send(KeychainCommand(.delete(ada)))
            for text in typed {
                sut.send(KeychainCommand(.setFilter(KeychainFilter(text: text))))
            }
            let bob = sut.snapshot.shownItems.first?.id
            let expectedCalls: [FakeKeychain.Call] = [.items, .add(added), .items, .delete(ada), .items]

            #expect(keychain.calls == expectedCalls)
            #expect(sut.snapshot.filter.text == "bob")
            #expect(sut.snapshot.shownItems.map(\.account) == ["bob"])
            #expect(bob != nil)
            #expect(bob != ada)
        }

        @Test("Installing reads nothing; leaving one of two drawers keeps the items, leaving the last drops them and the password but not the filter")
        func installCounting() throws {
            let firstSuite = "KeychainModelCommandTests.first.\(UUID().uuidString)"
            let secondSuite = "KeychainModelCommandTests.second.\(UUID().uuidString)"
            let firstDefaults = try #require(UserDefaults(suiteName: firstSuite))
            let secondDefaults = try #require(UserDefaults(suiteName: secondSuite))
            defer {
                firstDefaults.removePersistentDomain(forName: firstSuite)
                secondDefaults.removePersistentDomain(forName: secondSuite)
            }
            let first = DebugDrawer(defaults: firstDefaults)
            let second = DebugDrawer(defaults: secondDefaults)
            let keychain = FakeKeychain()
            let ada = keychain.seed(
                .genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"], value: Data("s3cr3t".utf8)
            )
            let model = KeychainModel(keychain: keychain)
            let sut = KeychainPlugin(model: model)
            first.registerGlobal(sut)
            second.registerGlobal(sut)
            let callsOnInstall = keychain.calls
            model.perform(KeychainCommand(.reload))
            model.perform(KeychainCommand(.toggle(ada)))
            model.perform(KeychainCommand(.setFilter(KeychainFilter(text: "ada"))))

            first.unregisterGlobal(id: sut.id)
            let keptWhileOneHolds = model.snapshot
            second.unregisterGlobal(id: sut.id)
            let droppedOnceNoneHolds = model.snapshot
            second.registerGlobal(sut)
            model.perform(KeychainCommand(.reload))

            #expect(callsOnInstall.isEmpty)
            #expect(keptWhileOneHolds.allItems.count == 1)
            #expect(keptWhileOneHolds.selection != nil)
            #expect(droppedOnceNoneHolds.contents == .unread)
            #expect(droppedOnceNoneHolds.selection == nil)
            #expect(droppedOnceNoneHolds.filter.text == "ada")
            #expect(model.snapshot.shownItems.map(\.account) == ["ada"])
        }

        @Test("Uninstalling from a drawer that never installed the plugin drops nothing")
        func uninstallFromAnotherDrawer() throws {
            let suite = "KeychainModelCommandTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let holder = DebugDrawer(defaults: defaults)
            let stranger = DebugDrawer(defaults: defaults)
            let keychain = FakeKeychain()
            keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"])
            let model = KeychainModel(keychain: keychain)
            let sut = KeychainPlugin(model: model)
            holder.registerGlobal(sut)
            model.perform(KeychainCommand(.reload))

            sut.uninstall(from: stranger)

            #expect(model.snapshot.allItems.count == 1)
        }
    }
#endif
