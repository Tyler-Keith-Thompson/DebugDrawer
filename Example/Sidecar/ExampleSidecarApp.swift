import DebugDrawerSidecarKit
import ExampleSidecarStore
import SwiftUI

// A company's sidecar app, built from the kit: it lists the apps in the example's app group that
// serve a sidecar (the production host, Example/Receiver; the iOS example's debug build), opens
// their sessions with a grant from the example's grant server, shows their Console and Network and
// a plugin for each capability the production host serves, and makes a report of what it shows.
// The capability plugins are the kit's generic plugin over each capability's model, one file each
// beside this one. On the Mac the store is the one `just run sidecar macOS` signed both apps for
// (ExampleSidecarStore).

@main
struct ExampleSidecarApp: App {
    var body: some Scene {
        WindowGroup {
            DebugDrawerSidecarView(
                apps: DebugDrawerSidecarAppList(storeDirectory: ExampleSidecarStore.directory),
                plugins: [
                    .featureFlagOverrides, .experimentOverrides, .logLevels, .tweaks, .localizationReview, .accessibilityEnvironment,
                    .analyticsEvents, .metricKitPayloads, .networkMocking, .diagnosticsCapture, .bugReports, .pushRegistration,
                    .scenarios, .authActions, .appStateReset, .environments, .performanceTraces, .appState, .console, .network
                ]
            ) { app in
                try ExampleGrantServer.grant(for: app)
            }
        }
    }
}
