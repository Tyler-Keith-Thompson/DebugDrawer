// The kit's plugins for the modules watchOS doesn't build (MetricKit, Network, Notifications,
// the Hang Detector) exist only on macOS and iOS, so the README's list compiles there.
#if DEBUG && os(macOS)
    import DebugDrawer
    import DebugDrawerAccessibility
    import DebugDrawerAnalytics
    import DebugDrawerAppInfo
    import DebugDrawerAppStateReset
    import DebugDrawerHangDetectorPlugin
    import DebugDrawerLocalization
    import DebugDrawerLocation
    import DebugDrawerMetricKit
    import DebugDrawerNetwork
    import DebugDrawerNotifications
    import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import DebugDrawerTweaks
    import SwiftUI
    import Testing

    // The README's sidecar for production builds ("Building a sidecar app with the kit"),
    // verbatim: it compiles against the kit's plugins.
    private struct CompanyProductionSidecar: View {
        var body: some View {
            DebugDrawerSidecarView(
                groupIdentifier: "group.com.example.debug",
                plugins: [
                    .featureFlagOverrides, .experimentOverrides, .logLevels, .tweaks, .localizationReview,
                    .accessibilityEnvironmentOverrides, .analyticsEvents, .metricKitPayloads, .networkMocking,
                    .diagnosticsCapture, .bugReports, .pushRegistration, .scenarios, .authActions, .appStateReset,
                    .environments, .locationSpoofing, .userDefaults, .performanceTraces, .appState
                ]
            )
        }
    }

    @MainActor
    struct SidecarCapabilityPluginsTests {
        @Test("The kit has a plugin for every capability the receiver ships, each under that capability's ID")
        func pluginPerCapability() {
            let expected: Set<String> = [
                DebugDrawerFeatureFlagOverrides.pluginID, DebugDrawerExperimentOverrides.pluginID, DebugDrawerLogLevels.pluginID,
                TweaksModel.pluginID, LocalizationReview.pluginID, AccessibilityEnvironmentOverrides.pluginID,
                AnalyticsEventsMirror.pluginID, MetricKitPayloadsMirror.pluginID, NetworkMocking.pluginID,
                DebugDrawerDiagnosticsCapture.pluginID, DebugDrawerBugReports.pluginID, PushRegistrationMirror.pluginID,
                DebugDrawerScenarios.pluginID, DebugDrawerAuthActions.pluginID, AppStateResetRequests.pluginID,
                DebugDrawerEnvironments.pluginID, LocationSpoofing.pluginID, DebugDrawerUserDefaults.pluginID,
                PerformanceTraces.pluginID, DebugDrawerAppState.pluginID
            ]
            let plugins: [DebugDrawerSidecarPlugin] = [
                .featureFlagOverrides, .experimentOverrides, .logLevels, .tweaks, .localizationReview,
                .accessibilityEnvironmentOverrides, .analyticsEvents, .metricKitPayloads, .networkMocking,
                .diagnosticsCapture, .bugReports, .pushRegistration, .scenarios, .authActions, .appStateReset,
                .environments, .locationSpoofing, .userDefaults, .performanceTraces, .appState
            ]

            let actual = plugins.map(\.id)

            #expect(Set(actual) == expected)
            #expect(actual.count == expected.count)
        }
    }
#endif
