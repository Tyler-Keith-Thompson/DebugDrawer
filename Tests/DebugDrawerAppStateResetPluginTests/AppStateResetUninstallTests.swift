#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerAppStateResetPlugin
    @testable import DebugDrawerAppStateReset
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    @MainActor
    @Suite("Reset App State drops the plan it read once removed from every drawer")
    struct AppStateResetUninstallTests {
        private static func drawer() throws -> (DebugDrawer, () -> Void) {
            let suite = temporarySuiteName("AppStateResetUninstallTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            return (DebugDrawer(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
        }

        @Test("Unregistering removes the plugin and drops the plan read, keeping the selection")
        func disappearsFromTheDrawer() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let model = AppStateResetModel(appState: seeded.appState, process: FakeAppProcess())
            let sut = AppStateResetPlugin(model: model)
            drawer.registerGlobal(sut)
            await model.loadIfNeeded()
            model.selection = [.userDefaults]
            let loadedPlan = model.state.plan

            drawer.unregisterGlobal(id: sut.id)

            #expect(loadedPlan != nil)
            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(model.state == .loading)
            #expect(model.selection == [.userDefaults])
        }

        @Test("Uninstalling twice is harmless, and once registered again the plan is read again")
        func uninstallTwiceThenReinstall() async throws {
            let seeded = try SeededAppState()
            defer { seeded.remove() }
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let model = AppStateResetModel(appState: seeded.appState, process: FakeAppProcess())
            let sut = AppStateResetPlugin(model: model)
            drawer.registerGlobal(sut)
            await model.loadIfNeeded()
            drawer.unregisterGlobal(id: sut.id)

            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)
            await model.loadIfNeeded()

            #expect(model.state.plan?.summary(of: .userDefaults) == "3 keys")
        }
    }
#endif
