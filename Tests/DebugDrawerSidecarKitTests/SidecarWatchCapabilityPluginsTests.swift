#if DEBUG && os(watchOS)
    import DebugDrawer
    import DebugDrawerAccessibility
    import DebugDrawerAnalytics
    import DebugDrawerLocalization
    import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import DebugDrawerTweaks
    import Testing
    import ViewInspector

    // The capabilities' plugins a watch sidecar can list: those whose modules build on watchOS.
    // MetricKit, Mocking and Push Registration don't, as their modules aren't built there.
    @MainActor
    struct SidecarWatchCapabilityPluginsTests {
        @Test("On watchOS the kit has the plugins of the capabilities whose modules build there, under their IDs")
        func watchPlugins() {
            let expected = [
                DebugDrawerFeatureFlagOverrides.pluginID, DebugDrawerExperimentOverrides.pluginID, DebugDrawerLogLevels.pluginID,
                TweaksModel.pluginID, LocalizationReview.pluginID, AccessibilityEnvironmentOverrides.pluginID,
                AnalyticsEventsMirror.pluginID, DebugDrawerDiagnosticsCapture.pluginID
            ]
            let plugins: [DebugDrawerSidecarPlugin] = [
                .featureFlagOverrides, .experimentOverrides, .logLevels, .tweaks, .localizationReview,
                .accessibilityEnvironmentOverrides, .analyticsEvents, .diagnosticsCapture
            ]

            let actual = plugins.map(\.id)

            #expect(actual == expected)
        }

        @Test("On watchOS a flag's switch sends its override, as on the phone")
        func flagSwitchSends() throws {
            let snapshot = DebugDrawerFeatureFlagOverrides.Snapshot(
                flags: [DebugDrawerFeatureFlag(key: "new-checkout", value: .bool(false))], overriddenKeys: []
            )
            var sent: [DebugDrawerFeatureFlagOverrides.Command] = []
            let sut = FeatureFlagOverridesView(snapshot: snapshot) { sent.append($0) }

            try sut.inspect().find(viewWithAccessibilityIdentifier: "Flag-new-checkout").find(ViewType.Toggle.self).tap()

            #expect(sent == [.setOverride(key: "new-checkout", value: .bool(true))])
        }
    }
#endif
