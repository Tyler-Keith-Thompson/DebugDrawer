import DebugDrawerNetwork
import DebugDrawerSidecarKit
import ExampleSidecarStore
import SwiftUI

// A company's sidecar app, built from the kit: it lists the apps in the example's app group that
// serve a sidecar (the production host, Example/Receiver; the iOS example's debug build), opens
// their sessions with a grant from the example's grant server, shows their Console and Network and
// the kit's plugin for each capability the production host serves, and makes a report of what it
// shows. The only thing of the example's own is Mocking's presets, for the host's Fetch Greeting.
// On the Mac the store is the one `just run sidecar macOS` signed both apps for
// (ExampleSidecarStore). `-ScriptSession <bundle ID>` opens a session with that app, overrides a
// flag in it and ends it, unattended (ExampleSessionScript).

@main
struct ExampleSidecarApp: App {
    init() {
        // `-ScriptSession <bundle ID>` drives a session with that app unattended.
        ExampleSessionScript.startIfAsked()
    }

    var body: some Scene {
        WindowGroup {
            DebugDrawerSidecarView(
                apps: DebugDrawerSidecarAppList(storeDirectory: ExampleSidecarStore.directory),
                plugins: [
                    .featureFlagOverrides, .experimentOverrides, .logLevels, .tweaks, .localizationReview,
                    .accessibilityEnvironmentOverrides, .analyticsEvents, .metricKitPayloads,
                    .networkMocking(presets: [.exampleGreeting], conditionPresets: [.exampleSlowGreeting]),
                    .diagnosticsCapture, .bugReports, .pushRegistration, .scenarios, .authActions, .appStateReset, .environments,
                    .locationSpoofing, .userDefaults, .performanceTraces, .appState, .console, .network
                ]
            ) { app in
                try ExampleGrantServer.grant(for: app)
            }
        }
    }
}

extension NetworkMockRule {
    /// Answers the example host's Fetch Greeting.
    fileprivate static let exampleGreeting = NetworkMockRule(
        name: "Mock Greeting",
        matcher: Matcher(methods: ["GET"], host: .exact("api.example.com"), path: .exact("/greeting")),
        response: Response(status: 200, body: .text("Hello from the sidecar"), contentType: "text/plain")
    )
}

extension NetworkConditionProfile {
    /// Holds the greeting's answer back two seconds.
    fileprivate static let exampleSlowGreeting = NetworkConditionProfile(
        name: "Slow Greeting", host: .exact("api.example.com"), latency: .seconds(2)
    )
}
