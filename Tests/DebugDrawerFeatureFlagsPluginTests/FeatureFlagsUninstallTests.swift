#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerFeatureFlagsPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite("Feature Flags takes its overrides out of the provider once removed from every drawer")
    struct FeatureFlagsUninstallTests {
        private static func drawer() throws -> (DebugDrawer, () -> Void) {
            let suite = "FeatureFlagsUninstallTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            return (DebugDrawer(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
        }

        @Test("Unregistering removes the plugin and clears the overrides from the provider, keeping them in storage")
        func disappearsFromTheDrawer() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let storage = FakeFeatureFlagOverrideStorage(["newCheckout": .bool(true), "theme": .string("dark")])
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "newCheckout", liveValue: .bool(false))])
            drawer.installFeatureFlags(provider: provider, storage: storage)
            let appliedOnceInstalled = provider.applied

            drawer.unregisterGlobal(id: "FeatureFlagsPlugin")

            #expect(appliedOnceInstalled == ["newCheckout": .bool(true), "theme": .string("dark")])
            #expect(!drawer.globalPlugins.contains { $0.id == "FeatureFlagsPlugin" })
            #expect(provider.applied.isEmpty)
            #expect(provider.currentValue(forKey: "newCheckout") == .bool(false))
            #expect(storage.values == ["newCheckout": .bool(true), "theme": .string("dark")])
        }

        @Test("Installing again over the same provider leaves the overrides applied")
        func installAgain() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let storage = FakeFeatureFlagOverrideStorage(["newCheckout": .bool(true)])
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "newCheckout", liveValue: .bool(false))])

            drawer.installFeatureFlags(provider: provider, storage: storage)
            drawer.installFeatureFlags(provider: provider, storage: storage)

            #expect(drawer.globalPlugins.count { $0.id == "FeatureFlagsPlugin" } == 1)
            #expect(provider.applied == ["newCheckout": .bool(true)])
        }

        @Test("Uninstalling twice clears once, and a plugin registered again applies the overrides again")
        func uninstallTwiceThenReinstall() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let storage = FakeFeatureFlagOverrideStorage(["newCheckout": .bool(true)])
            let provider = FakeFeatureFlagProvider()
            let sut = FeatureFlagsPlugin(store: FeatureFlagStore(provider: provider, storage: storage))
            drawer.registerGlobal(sut)
            drawer.unregisterGlobal(id: sut.id)

            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)

            #expect(provider.calls == [.set("newCheckout", .bool(true)), .clear("newCheckout"), .set("newCheckout", .bool(true))])
            #expect(provider.applied == ["newCheckout": .bool(true)])
        }
    }
#endif
