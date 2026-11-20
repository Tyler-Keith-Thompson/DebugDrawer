import DebugDrawerAccessibility
import DebugDrawerLocalization
import SwiftUI

// A production app's view of DebugDrawer, on the Mac and on iOS: it links the receiver and the
// capability modules and nothing else of the library, so its release build carries no drawer, no
// plugin and no interception (`just release-check` builds it optimized). It serves the example
// sidecar (Example/Sidecar) every capability the library ships: feature flag overrides,
// production-safe tweaks, localization review, accessibility overrides, analytics events,
// MetricKit payloads and network mocking, within sessions of at most 15 minutes that open only
// with a grant the example's grant server signed. Each capability has something on the screen
// that changes as the sidecar acts, and the app draws its own indicator while a session is open.
// `just run sidecar` (iOS) and `just run sidecar macOS` launch it beside the sidecar.

@main
struct ExampleReceiverApp: App {
    @StateObject private var host = ExampleReceiverHost()

    var body: some Scene {
        WindowGroup {
            ExampleReceiverScreen(host: host, flags: host.flags, sessions: host.sessions, keeper: host.keeper, mocking: host.mocking)
                .localizationReview()
                .accessibilityEnvironmentOverrides()
        }
    }
}
