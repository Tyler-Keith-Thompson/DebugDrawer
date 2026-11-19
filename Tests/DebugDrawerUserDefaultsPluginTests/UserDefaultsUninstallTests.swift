#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerUserDefaultsPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite("UserDefaults stops following the app's writes once removed from every drawer")
    struct UserDefaultsUninstallTests {
        private static func drawer() throws -> (DebugDrawer, () -> Void) {
            let suite = "UserDefaultsUninstallTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            return (DebugDrawer(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
        }

        @Test("Unregistering while shown removes the plugin, removes its change observer and drops the keys, leaving the defaults")
        func disappearsFromTheDrawer() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let storage = FakeUserDefaultsStorage(suites: [.standard: ["launchCount": 1]])
            let model = UserDefaultsModel(suites: [], storage: storage)
            let sut = UserDefaultsPlugin(model: model)
            drawer.registerGlobal(sut)
            model.startObservingChanges()
            model.startObservingChanges()
            model.searchText = "launch"
            let observersWhileShown = storage.observerCount

            drawer.unregisterGlobal(id: sut.id)

            #expect(observersWhileShown == 1)
            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(storage.observerCount == 0)
            #expect(model.entries.isEmpty)
            #expect(model.searchText == "launch")
            #expect(storage.suites[.standard]?["launchCount"] as? Int == 1)
        }

        @Test("Views that disappear after the plugin is removed change nothing, and a reinstalled plugin follows changes again")
        func lateDisappearanceThenReinstall() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let storage = FakeUserDefaultsStorage()
            let model = UserDefaultsModel(suites: [], storage: storage)
            let sut = UserDefaultsPlugin(model: model)
            drawer.registerGlobal(sut)
            model.startObservingChanges()
            drawer.unregisterGlobal(id: sut.id)

            model.stopObservingChanges()
            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)
            model.startObservingChanges()
            let followingOnceReinstalled = storage.observerCount
            model.stopObservingChanges()

            #expect(followingOnceReinstalled == 1)
            #expect(storage.observerCount == 0)
        }
    }
#endif
