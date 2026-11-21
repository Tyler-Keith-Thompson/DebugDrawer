#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerKeychainPlugin
    import DebugDrawerTestSupport
    import Foundation
    import Security
    import Testing

    @MainActor
    @Suite("Keychain drops the items and passwords it read once removed from every drawer")
    struct KeychainUninstallTests {
        private static func drawer() throws -> (DebugDrawer, () -> Void) {
            let suite = temporarySuiteName("KeychainUninstallTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            return (DebugDrawer(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
        }

        private static func keychain() -> FakeKeychain {
            let keychain = FakeKeychain()
            keychain.seed(.genericPassword, [kSecAttrService as String: "com.example.App", kSecAttrAccount as String: "ada"])
            return keychain
        }

        @Test("Unregistering removes the plugin and drops the items, the open password and the form, leaving the keychain")
        func disappearsFromTheDrawer() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let keychain = Self.keychain()
            let model = KeychainModel(keychain: keychain)
            let sut = KeychainPlugin(model: model)
            drawer.registerGlobal(sut)
            model.reload()
            let item = try #require(model.shownItems.first)
            model.toggle(item)
            model.startAdding()
            model.filter.text = "ada"
            let openWhileInstalled = model.selection != nil

            drawer.unregisterGlobal(id: sut.id)

            #expect(openWhileInstalled)
            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(model.contents == .unread)
            #expect(model.selection == nil)
            #expect(model.editor == nil)
            #expect(model.filter.text == "ada")
            #expect(try keychain.items().count == 1)
        }

        @Test("Uninstalling twice is harmless, and a plugin registered again reads the keychain again")
        func uninstallTwiceThenReinstall() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let model = KeychainModel(keychain: Self.keychain())
            let sut = KeychainPlugin(model: model)
            drawer.registerGlobal(sut)
            drawer.unregisterGlobal(id: sut.id)

            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)
            model.reload()

            #expect(model.shownItems.map(\.account) == ["ada"])
        }
    }
#endif
