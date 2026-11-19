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
            let storage = FakeUserDefaultsStorage(suites: [.standard: ["launchCount": .number(1)]])
            let model = UserDefaultsModel(suites: [], storage: storage)
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let sut = UserDefaultsPlugin(model: model)
            drawer.registerGlobal(sut)
            transport.send(UserDefaultsCommand(.startObserving))
            transport.send(UserDefaultsCommand(.startObserving))
            transport.send(UserDefaultsCommand(.setSearchText("launch")))
            let observersWhileShown = storage.observerCount
            let entriesWhileShown = transport.snapshot.entries.count

            drawer.unregisterGlobal(id: sut.id)

            #expect(observersWhileShown == 1)
            #expect(entriesWhileShown == 1)
            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(storage.observerCount == 0)
            #expect(transport.snapshot.entries.isEmpty)
            #expect(transport.snapshot.searchText == "launch")
            #expect(storage.suites[.standard]?["launchCount"] == .number(1))
        }

        @Test("Views that disappear after the plugin is removed change nothing, and a reinstalled plugin follows changes again")
        func lateDisappearanceThenReinstall() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let storage = FakeUserDefaultsStorage()
            let model = UserDefaultsModel(suites: [], storage: storage)
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let sut = UserDefaultsPlugin(model: model)
            drawer.registerGlobal(sut)
            transport.send(UserDefaultsCommand(.startObserving))
            drawer.unregisterGlobal(id: sut.id)

            transport.send(UserDefaultsCommand(.stopObserving))
            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)
            transport.send(UserDefaultsCommand(.startObserving))
            let followingOnceReinstalled = storage.observerCount
            transport.send(UserDefaultsCommand(.stopObserving))

            #expect(followingOnceReinstalled == 1)
            #expect(storage.observerCount == 0)
        }

        @Test("Installed in two drawers, the plugin keeps following until the last removes it")
        func installCountingAcrossDrawers() throws {
            let (first, cleanUpFirst) = try Self.drawer()
            defer { cleanUpFirst() }
            let (second, cleanUpSecond) = try Self.drawer()
            defer { cleanUpSecond() }
            let storage = FakeUserDefaultsStorage(suites: [.standard: ["a": .string("b")]])
            let model = UserDefaultsModel(suites: [], storage: storage)
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let sut = UserDefaultsPlugin(model: model)
            first.registerGlobal(sut)
            second.registerGlobal(sut)
            transport.send(UserDefaultsCommand(.startObserving))

            first.unregisterGlobal(id: sut.id)
            let observersAfterFirst = storage.observerCount
            let entriesAfterFirst = transport.snapshot.entries.count
            second.unregisterGlobal(id: sut.id)

            #expect(observersAfterFirst == 1)
            #expect(entriesAfterFirst == 1)
            #expect(storage.observerCount == 0)
            #expect(transport.snapshot.entries.isEmpty)
        }

        @Test("Uninstalling from a drawer that never installed the plugin changes nothing")
        func strangerDrawer() throws {
            let (installed, cleanUpInstalled) = try Self.drawer()
            defer { cleanUpInstalled() }
            let (stranger, cleanUpStranger) = try Self.drawer()
            defer { cleanUpStranger() }
            let storage = FakeUserDefaultsStorage(suites: [.standard: ["a": .string("b")]])
            let model = UserDefaultsModel(suites: [], storage: storage)
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let sut = UserDefaultsPlugin(model: model)
            installed.registerGlobal(sut)
            transport.send(UserDefaultsCommand(.startObserving))

            sut.uninstall(from: stranger)

            #expect(storage.observerCount == 1)
            #expect(transport.snapshot.entries.count == 1)
            transport.send(UserDefaultsCommand(.stopObserving))
        }
    }
#endif
