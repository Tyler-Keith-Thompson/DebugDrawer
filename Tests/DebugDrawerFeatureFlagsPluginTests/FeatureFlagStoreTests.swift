#if DEBUG
    @testable import DebugDrawerFeatureFlagsPlugin
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FeatureFlagStoreTests {
        /// Stands in for the drawer a store is installed in.
        private static let drawer = ObjectIdentifier(FeatureFlagStoreTests.self)

        @Test("An override is stored and applied to the provider, so the app reads it")
        func setOverride() {
            let storage = FakeFeatureFlagOverrideStorage()
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "newCheckout", liveValue: .bool(false))])
            let sut = FeatureFlagStore(provider: provider, storage: storage)

            sut.setOverride(.bool(true), forKey: "newCheckout")

            #expect(storage.values == ["newCheckout": .bool(true)])
            #expect(provider.calls == [.set("newCheckout", .bool(true))])
            #expect(provider.currentValue(forKey: "newCheckout") == .bool(true))
        }

        @Test("Overrides persist: a fresh store over the same storage applies them to a fresh provider once installed, as on the next launch")
        func persistsAcrossLaunches() {
            let storage = FakeFeatureFlagOverrideStorage()
            let flags = [FeatureFlag(key: "newCheckout", liveValue: .bool(false)), FeatureFlag(key: "discount", liveValue: .number(0))]
            let firstLaunch = FeatureFlagStore(provider: FakeFeatureFlagProvider(flags), storage: storage)
            firstLaunch.setOverride(.number(0.2), forKey: "discount")
            firstLaunch.setOverride(.bool(true), forKey: "newCheckout")
            let provider = FakeFeatureFlagProvider(flags)

            let sut = FeatureFlagStore(provider: provider, storage: storage)
            sut.install(in: Self.drawer)

            #expect(provider.calls == [.set("discount", .number(0.2)), .set("newCheckout", .bool(true))])
            #expect(sut.rows.map(\.override) == [.bool(true), .number(0.2)])
            #expect(sut.rows.map(\.control) == [.toggle(true), .number(0.2)])
        }

        @Test("Overrides persist in UserDefaults: a fresh store over the same defaults applies them once installed")
        func persistsInUserDefaults() throws {
            let suiteName = temporarySuiteName("com.debugdrawer.tests.featureFlags")
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let flags = [FeatureFlag(key: "theme", liveValue: .string("light"))]
            FeatureFlagStore(provider: FakeFeatureFlagProvider(flags), storage: UserDefaultsFeatureFlagOverrideStorage(defaults: defaults))
                .setOverride(.string("dark"), forKey: "theme")
            let provider = FakeFeatureFlagProvider(flags)

            FeatureFlagStore(provider: provider, storage: UserDefaultsFeatureFlagOverrideStorage(defaults: defaults)).install(in: Self.drawer)

            #expect(provider.currentValue(forKey: "theme") == .string("dark"))
        }

        @Test("Clearing one override removes it from storage and the provider, and leaves the others")
        func clearOne() {
            let storage = FakeFeatureFlagOverrideStorage(["a": .bool(true), "b": .string("x")])
            let provider = FakeFeatureFlagProvider()
            let sut = FeatureFlagStore(provider: provider, storage: storage)
            sut.install(in: Self.drawer)
            provider.calls = []

            sut.clearOverride(forKey: "a")

            #expect(storage.values == ["b": .string("x")])
            #expect(provider.calls == [.clear("a")])
            #expect(provider.applied == ["b": .string("x")])
        }

        @Test("Clearing all removes every stored override, a flag the provider no longer lists included")
        func clearAll() {
            let storage = FakeFeatureFlagOverrideStorage(["listed": .bool(true), "removedFlag": .number(3)])
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "listed", liveValue: .bool(false))])
            let sut = FeatureFlagStore(provider: provider, storage: storage)
            provider.calls = []

            sut.clearAllOverrides()

            #expect(storage.values.isEmpty)
            #expect(provider.calls == [.clear("listed"), .clear("removedFlag")])
            #expect(provider.applied.isEmpty)
        }

        @Test("Clearing all with no overrides calls nothing")
        func clearAllEmpty() {
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "a", liveValue: .bool(false))])
            let sut = FeatureFlagStore(provider: provider, storage: FakeFeatureFlagOverrideStorage())

            sut.clearAllOverrides()

            #expect(provider.calls.isEmpty)
        }

        @Test("A number override that isn't finite is ignored", arguments: [Double.nan, .infinity, -.infinity])
        func nonFinite(number: Double) {
            let storage = FakeFeatureFlagOverrideStorage()
            let provider = FakeFeatureFlagProvider()
            let sut = FeatureFlagStore(provider: provider, storage: storage)

            sut.setOverride(.number(number), forKey: "discount")

            #expect(storage.values.isEmpty)
            #expect(provider.calls.isEmpty)
        }

        @Test("A store tells its observers before each change")
        func objectWillChange() {
            let sut = FeatureFlagStore(provider: FakeFeatureFlagProvider(), storage: FakeFeatureFlagOverrideStorage())
            var actual = 0
            let subscription = sut.objectWillChange.sink { actual += 1 }
            defer { subscription.cancel() }

            sut.setOverride(.bool(true), forKey: "a")
            sut.clearOverride(forKey: "a")
            sut.refresh()

            #expect(actual == 3)
        }

        @Test("Rows follow the provider's order and show what it lists now")
        func rowsFollowProvider() {
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "b", liveValue: .bool(false)), FeatureFlag(key: "a", liveValue: .bool(false))])
            let sut = FeatureFlagStore(provider: provider, storage: FakeFeatureFlagOverrideStorage())
            let before = sut.rows.map(\.id)
            provider.flagList.append(FeatureFlag(key: "c", liveValue: .string("new")))

            let actual = sut.rows.map(\.id)

            #expect(before == ["b", "a"])
            #expect(actual == ["b", "a", "c"])
        }

        @Test("With no flags and no overrides, the store has no rows")
        func empty() {
            let sut = FeatureFlagStore(provider: FakeFeatureFlagProvider(), storage: FakeFeatureFlagOverrideStorage())

            #expect(sut.rows.isEmpty)
            #expect(sut.overrides.isEmpty)
        }
    }
#endif
