#if DEBUG
    @testable import DebugDrawer
    import DebugDrawerTestSupport
    @testable import DebugDrawerTweaksPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite("Tweaks leaves the drawer and keeps the app reading through its storage")
    struct TweaksUninstallTests {
        @Test("Unregistering removes the plugin; the app's tweaks still read the storage installTweaks gave")
        func disappearsFromTheDrawer() throws {
            let suite = temporarySuiteName("TweaksUninstallTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let storage = FakeTweakStorage(["tweaks.test.uninstall": .bool(true)])
            let tweak = Tweak.toggle("Uninstall test", key: "tweaks.test.uninstall", default: false)
            drawer.installTweaks(storage: storage) {
                TweakSection("Uninstall") { tweak }
            }

            drawer.unregisterGlobal(id: "TweaksPlugin")

            #expect(!drawer.globalPlugins.contains { $0.id == "TweaksPlugin" })
            #expect(TweakStore.shared.storage as? FakeTweakStorage === storage)
            #expect(tweak.value)
            #expect(storage.values == ["tweaks.test.uninstall": .bool(true)])
        }

        @Test("Uninstalling twice is harmless, and a plugin registered again lists its actions again")
        func uninstallTwiceThenReinstall() throws {
            let suite = temporarySuiteName("TweaksUninstallTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let sut = TweaksPlugin(sections: [TweakSection("Session") { TweakAction("Expire token") {} }])
            drawer.registerGlobal(sut)
            drawer.unregisterGlobal(id: sut.id)

            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)

            #expect(drawer.globalPlugins.filter { $0.id == sut.id }.map(\.actions.count) == [1])
        }
    }
#endif
