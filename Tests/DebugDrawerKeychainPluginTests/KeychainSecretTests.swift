#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerKeychainPlugin
    import Foundation
    import Security
    import Testing

    // A snapshot can leave the app through a transport, so it must never hold a password. Each
    // test drives a model over the in-memory FakeKeychain into a state that has read passwords,
    // encodes the snapshot as a transport would, and looks for every secret in the bytes: as text,
    // as its UTF-8 bytes, base64 (how JSONEncoder writes Data) and hexadecimal.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct KeychainSecretTests {
        @Test("No snapshot holds a password: unread, listed, revealed, revealed binary, edit open, edit refused, read refused, add refused")
        func noSecretInAnyState() throws {
            let textSecret = "hunter2-correct-horse"
            let binarySecret = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x7F, 0x13, 0x37])
            let editedSecret = "battery-staple-42"
            let keychain = FakeKeychain()
            let ada = keychain.seed(
                .genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"], value: Data(textSecret.utf8)
            )
            let bob = keychain.seed(
                .internetPassword, [kSecAttrServer as String: "example.com", kSecAttrAccount as String: "bob"], value: binarySecret
            )
            let model = KeychainModel(keychain: keychain)
            let sut = DebugDrawerPluginTransport.direct(to: model)
            var snapshots = [sut.snapshot]

            sut.send(KeychainCommand(.reload))
            snapshots.append(sut.snapshot)
            sut.send(KeychainCommand(.toggle(ada)))
            snapshots.append(sut.snapshot)
            sut.send(KeychainCommand(.toggle(bob)))
            snapshots.append(sut.snapshot)
            sut.send(KeychainCommand(.startEditing(ada)))
            snapshots.append(sut.snapshot)
            keychain.refusal = KeychainError(status: errSecInteractionNotAllowed)
            let edit = try #require(sut.snapshot.editor?.draft)
            sut.send(KeychainCommand(.save(GenericPassword(
                service: edit.service, account: edit.account, value: editedSecret, accessGroup: edit.accessGroup
            ))))
            snapshots.append(sut.snapshot)
            sut.send(KeychainCommand(.cancelEditing))
            sut.send(KeychainCommand(.startEditing(ada)))
            snapshots.append(sut.snapshot)
            keychain.refusal = nil
            sut.send(KeychainCommand(.startAdding))
            keychain.refusal = KeychainError(status: errSecInteractionNotAllowed)
            sut.send(KeychainCommand(.save(GenericPassword(service: "com.example.New", account: "eve", value: editedSecret))))
            snapshots.append(sut.snapshot)
            let secrets = [Data(textSecret.utf8), binarySecret, Data(editedSecret.utf8)]
            let forms = secrets.flatMap { secret in
                [secret, Data(secret.base64EncodedString().utf8), Data(secret.map { String(format: "%02x", $0) }.joined().utf8)]
            }
            let readInProcess = [model.revealedValue(for: ada), model.revealedValue(for: bob)]

            // Unescaped, so a base64 "/" reads as itself rather than "\/".
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            let encoded = try snapshots.map { try encoder.encode($0) }
            let leaks = encoded.enumerated().flatMap { index, json in
                forms.filter { json.range(of: $0) != nil }.map { "snapshot \(index) holds \($0.base64EncodedString())" }
            }

            #expect(leaks.isEmpty)
            #expect(snapshots.count == 8)
            #expect(snapshots[2].selection?.value == .held)
            #expect(snapshots[3].selection?.value == .held)
            #expect(snapshots[4].editor != nil)
            #expect(snapshots[5].issue?.action == "Couldn't save")
            #expect(snapshots[6].issue?.action == "Couldn't read the password")
            #expect(snapshots[7].editor != nil)
            #expect(readInProcess == [nil, binarySecret])
        }

        @Test("A snapshot built with a form holding a password holds the form with its password emptied")
        func formPasswordEmptied() throws {
            let draft = GenericPassword(service: "com.example.App", account: "ada", value: "hunter2", accessGroup: "TEAMID.com.example.app")
            let expected = GenericPassword(service: "com.example.App", account: "ada", accessGroup: "TEAMID.com.example.app")

            let sut = KeychainSnapshot(editor: .editing(KeychainFixtures.password, draft))
            let json = try JSONEncoder().encode(sut)

            #expect(sut.editor == .editing(KeychainFixtures.password, expected))
            #expect(json.range(of: Data("hunter2".utf8)) == nil)
        }

        @Test("The password read for an item is the open item's, or the edit form's start, and none once both close")
        func revealedValueInProcess() throws {
            let keychain = FakeKeychain()
            let ada = keychain.seed(
                .genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"], value: Data("s3cr3t".utf8)
            )
            let model = KeychainModel(keychain: keychain)
            model.perform(KeychainCommand(.reload))
            let unopened = model.revealedValue(for: ada)

            model.perform(KeychainCommand(.startEditing(ada)))
            let editing = model.revealedValue(for: ada)
            model.perform(KeychainCommand(.cancelEditing))
            let cancelled = model.revealedValue(for: ada)

            #expect(unopened == nil)
            #expect(editing == Data("s3cr3t".utf8))
            #expect(cancelled == nil)
        }
    }
#endif
