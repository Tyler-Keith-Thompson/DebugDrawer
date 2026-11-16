#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerFeatureFlagsPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FeatureFlagsPluginTests {
        @Test("The plugin is Feature Flags, in the App category")
        func identity() {
            let sut = FeatureFlagsPlugin(store: FeatureFlagStore(provider: FakeFeatureFlagProvider(), storage: FakeFeatureFlagOverrideStorage()))

            #expect(sut.title == "Feature Flags")
            #expect(sut.category == "App")
            #expect(sut.icon == "flag")
        }

        @Test("Installing registers one Feature Flags plugin, with no other plugin installed, and installing again replaces it")
        func install() {
            let drawer = DebugDrawer.shared
            let storage = FakeFeatureFlagOverrideStorage()

            drawer.installFeatureFlags(provider: FakeFeatureFlagProvider(), storage: storage)
            drawer.installFeatureFlags(provider: FakeFeatureFlagProvider(), storage: storage)

            let actual = drawer.globalPlugins.filter { $0.id == "FeatureFlagsPlugin" }
            drawer.unregisterGlobal(id: "FeatureFlagsPlugin")
            #expect(actual.count == 1)
            #expect(actual.map(\.contributesToReport) == [true])
        }

        @Test("Installing applies every stored override to the provider before returning")
        func installApplies() {
            let storage = FakeFeatureFlagOverrideStorage(["newCheckout": .bool(true)])
            let provider = FakeFeatureFlagProvider([FeatureFlag(key: "newCheckout", liveValue: .bool(false))])

            DebugDrawer.shared.installFeatureFlags(provider: provider, storage: storage)

            DebugDrawer.shared.unregisterGlobal(id: "FeatureFlagsPlugin")
            #expect(provider.currentValue(forKey: "newCheckout") == .bool(true))
        }

        @Test("The drawer's search offers clearing every override, found by \"flags\" too")
        func action() throws {
            let storage = FakeFeatureFlagOverrideStorage(["a": .bool(true), "b": .number(2)])
            let provider = FakeFeatureFlagProvider()
            let sut = FeatureFlagsPlugin(store: FeatureFlagStore(provider: provider, storage: storage))

            let actual = try #require(sut.actions.first)
            actual.perform()

            #expect(sut.actions.map(\.title) == ["Clear feature flag overrides"])
            #expect(actual.keywords.contains("flags"))
            #expect(storage.values.isEmpty)
            #expect(provider.applied.isEmpty)
        }

        @Test("The report gets flags.json with each flag's title, live value, override and the value in use, a token masked")
        func report() throws {
            let rows = [
                FeatureFlagRowState(
                    FeatureFlag(key: "newCheckout", liveValue: .bool(false), title: "New checkout"),
                    currentValue: .bool(true),
                    override: .bool(true)
                ),
                FeatureFlagRowState(FeatureFlag(key: "discount", liveValue: .number(0.1)), currentValue: .number(0.1), override: nil),
                FeatureFlagRowState(
                    FeatureFlag(key: "apiToken", liveValue: .string("live-t0k3n")),
                    currentValue: .string("t0k3n"),
                    override: .string("t0k3n")
                )
            ]
            let expected = """
            {
              "apiToken" : {
                "liveValue" : "[REDACTED]",
                "override" : "[REDACTED]",
                "title" : "apiToken",
                "value" : "[REDACTED]"
              },
              "discount" : {
                "liveValue" : "0.1",
                "title" : "discount",
                "value" : "0.1"
              },
              "newCheckout" : {
                "liveValue" : "false",
                "override" : "true",
                "title" : "New checkout",
                "value" : "true"
              }
            }
            """
            var actual = DebugDrawerReport()

            FeatureFlagsPlugin.contribute(rows, to: &actual, redaction: .standard)

            let file = try #require(actual.files.first)
            #expect(file.name == "flags.json")
            #expect(file.kind == .json)
            #expect(String(bytes: file.data, encoding: .utf8) == expected)
        }

        @Test("No flags add nothing to the report")
        func reportEmpty() {
            var actual = DebugDrawerReport()

            FeatureFlagsPlugin.contribute([], to: &actual, redaction: .standard)

            #expect(actual.files.isEmpty)
        }
    }
#endif
