// The README's Feature Flags example, verbatim, so the README cannot drift from the code. It lives
// here rather than in DebugDrawerTests, which links core alone.

#if DEBUG
    import DebugDrawer
    import DebugDrawerFeatureFlagsPlugin
    import Testing

    /// The app's own flag service, adapted for the drawer: live values from the server, and overrides
    /// that win over them.
    final class AppFlags: FeatureFlagProvider {
        var live: [String: FeatureFlagValue] = ["new-checkout": .bool(false), "discount": .number(0.1)]
        private var overrides: [String: FeatureFlagValue] = [:]

        func flags() -> [FeatureFlag] {
            live.sorted { $0.key < $1.key }.map { FeatureFlag(key: $0.key, liveValue: $0.value) }
        }

        func currentValue(forKey key: String) -> FeatureFlagValue? {
            overrides[key] ?? live[key]
        }

        func setOverride(_ value: FeatureFlagValue, forKey key: String) {
            overrides[key] = value
        }

        func clearOverride(forKey key: String) {
            overrides[key] = nil
        }
    }

    @MainActor
    @Suite("README examples")
    struct READMEExamplesTests {
        @Test("Feature Flags")
        func featureFlags() {
            let appFlags = AppFlags()

            DebugDrawer.shared.installFeatureFlags(provider: appFlags)

            // Anywhere in the app, through the adapter, so overrides apply:
            let isNewCheckout = appFlags.currentValue(forKey: "new-checkout") == .bool(true)

            // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
            DebugDrawer.shared.unregisterGlobal(id: "FeatureFlagsPlugin")
            #expect(appFlags.flags().map(\.key) == ["discount", "new-checkout"])
            // The test process's defaults hold no overrides, so the live value is read.
            #expect(!isNewCheckout)
        }
    }
#endif
