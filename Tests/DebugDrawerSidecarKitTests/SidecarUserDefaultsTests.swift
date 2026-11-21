#if DEBUG && os(macOS)
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import DebugDrawerTestSupport
    import Foundation
    import Testing
    import ViewInspector

    // An edit from the sidecar's editor to the production app's receiver: the kit lists the app,
    // shows its allowlisted keys through the UserDefaults plugin over the store, and the switch
    // leaves the edit in the store, where the receiver performs it in the session and audits it
    // with the key's value before and after. Each wait is for the snapshot that step should
    // produce, never for time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)), .serialized)
    struct SidecarUserDefaultsTests {
        private let plan = DebugDrawerUserDefaults.Entry(key: "plan", title: "Plan", kind: .choice(options: ["free", "pro"]), value: .string("free"))
        private let tips = DebugDrawerUserDefaults.Entry(key: "showsTips", title: "Shows Tips", kind: .bool, value: .bool(true))
        private let items = DebugDrawerUserDefaults.Entry(key: "itemsPerPage", title: "Items per Page", kind: .integer(range: 10 ... 100), value: nil)

        @Test("The kit lists the app's allowlisted keys, and the switch edits the key in the app, audited with its old and new value")
        func switchEditsTheKey() async throws {
            let suite = temporarySuiteName("SidecarUserDefaultsTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarUserDefaultsTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let model = DebugDrawerUserDefaults(.bool("showsTips", title: "Shows Tips"), defaults: defaults)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.userDefaults(model))
            try receiver.start()
            defer { receiver.stop() }
            sessions.perform(.open(duration: 60))
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let sut = try DebugDrawerSidecarConnection(app: listed)
            defer { sut.close() }
            let hosted = try await sut.host(.userDefaults)
            let expectedChanges = [DebugDrawerAuditEntry.Change(key: "showsTips", oldValue: nil, newValue: .bool(true))]

            try hosted.body.inspect().find(viewWithAccessibilityIdentifier: "UserDefaults-showsTips").find(ViewType.Toggle.self).tap()

            for await snapshot in model.$snapshot.values where snapshot.entries.first?.value == .bool(true) {
                break
            }
            #expect(listed.serves(DebugDrawerUserDefaults.pluginID))
            #expect(defaults.object(forKey: "showsTips") as? Bool == true)
            #expect(sessions.auditLog.last?.event == .commandApplied)
            #expect(sessions.auditLog.last?.changes == expectedChanges)
        }

        @Test("Each key shows its value; the switch and picker send their key's edit, Remove a removal, Revert All a revert")
        func viewSendsEdits() throws {
            let snapshot = DebugDrawerUserDefaults.Snapshot(entries: [plan, tips, items], editedKeys: ["plan"])
            var sent: [DebugDrawerUserDefaults.Command] = []
            let sut = UserDefaultsEditorView(snapshot: snapshot) { sent.append($0) }

            try sut.inspect().find(viewWithAccessibilityIdentifier: "UserDefaults-showsTips").find(ViewType.Toggle.self).tap()
            try sut.inspect().find(viewWithAccessibilityIdentifier: "UserDefaults-plan").find(ViewType.Picker.self).select(value: "pro")
            try sut.inspect().find(viewWithAccessibilityIdentifier: "UserDefaults-plan").find(button: "Remove").tap()
            try sut.inspect().find(button: "Revert All").tap()

            #expect(sent == [
                .set(key: "showsTips", value: .bool(false)),
                .set(key: "plan", value: .string("pro")),
                .remove(key: "plan"),
                .revertAll
            ])
            #expect(throws: Never.self) { try sut.inspect().find(viewWithAccessibilityIdentifier: "UserDefaults-plan").find(text: "Edited") }
            #expect(throws: Never.self) { try sut.inspect().find(viewWithAccessibilityIdentifier: "UserDefaults-itemsPerPage").find(text: "Not set") }
            #expect(throws: (any Error).self) {
                try sut.inspect().find(viewWithAccessibilityIdentifier: "UserDefaults-itemsPerPage").find(button: "Remove")
            }
            #expect(throws: Never.self) {
                try sut.inspect().find(viewWithAccessibilityIdentifier: "UserDefaults-itemsPerPage").find(text: "A whole number from 10 to 100")
            }
        }

        @Test("A number field's Set sends only text its key's kind takes: in bounds, and a number of the key's kind")
        func fieldTextBecomesValueOnlyWhenTaken() {
            let integer = DebugDrawerUserDefaultsKey.Kind.integer(range: 10 ... 100)
            let double = DebugDrawerUserDefaultsKey.Kind.double(range: 0 ... 0.5)
            let string = DebugDrawerUserDefaultsKey.Kind.string(maximumLength: 3)

            let actual: [DebugDrawerUserDefaultsValue?] = [
                integer.value(from: " 25 "), integer.value(from: "101"), integer.value(from: "2.5"), integer.value(from: "ten"),
                double.value(from: "0.25"), double.value(from: "0.6"), double.value(from: "nan"),
                string.value(from: "Hi!"), string.value(from: "Hello")
            ]

            #expect(actual == [.integer(25), nil, nil, nil, .double(0.25), nil, nil, .string("Hi!"), nil])
        }

        @Test("With no key allowlisted the plugin says so and offers no Revert All")
        func emptyAllowlist() throws {
            let sut = UserDefaultsEditorView(snapshot: DebugDrawerUserDefaults.Snapshot(entries: [], editedKeys: [])) { _ in }

            #expect(throws: Never.self) { try sut.inspect().find(text: "The app allowlists no UserDefaults key.") }
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Revert All") }
        }

        @Test("The shipped UserDefaults plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.userDefaults

            #expect([sut.id, sut.title, sut.icon] == [DebugDrawerUserDefaults.pluginID, "UserDefaults", "cylinder.split.1x2"])
        }
    }
#endif
