import DebugDrawerAccessibility
import DebugDrawerLocalization
import SwiftUI

// A production app's view of DebugDrawer, on the Mac and on iOS: it links the receiver and the
// capability modules and nothing else of the library, so its release build carries no drawer, no
// plugin and no interception (`just release-check` builds it optimized). It serves the example
// sidecar (Example/Sidecar) every capability the library ships: feature flag overrides,
// experiment overrides, log levels, production-safe tweaks, localization review, accessibility
// overrides, analytics events, MetricKit payloads, network mocking, diagnostics capture, bug
// reports, push registration, scenarios, auth actions and an app state reset, within sessions of at most 15 minutes that open only
// with a grant the example's grant server signed. Each capability has something on the screen that
// changes as the sidecar acts, and the app draws its own indicator while a session is open. `just
// run sidecar` (iOS) and `just run sidecar macOS` launch it beside the sidecar.

@main
struct ExampleReceiverApp: App {
    #if os(macOS)
        @NSApplicationDelegateAdaptor private var delegate: ExampleReceiverAppDelegate
    #else
        @UIApplicationDelegateAdaptor private var delegate: ExampleReceiverAppDelegate
    #endif

    /// The host, which the app delegate owns so it can hand it the APNs device token.
    private var host: ExampleReceiverHost {
        delegate.host
    }

    var body: some Scene {
        WindowGroup {
            ExampleReceiverScreen(
                host: host, flags: host.flags, experiments: host.experiments, logging: host.logging, scenarios: host.scenarios,
                signIn: host.signIn, appState: host.appState, sessions: host.sessions,
                keeper: host.keeper, mocking: host.mocking, diagnostics: host.diagnostics,
                backend: host.environments.backend, environments: host.environments.model,
                performance: host.performance, traces: host.performance.traces
            )
            .localizationReview()
            .accessibilityEnvironmentOverrides()
        }
        .commands {
            // The host's own trigger for a bug report, beside the screen's button: DebugDrawer binds
            // no key or gesture.
            CommandMenu("Feedback") {
                Button("Report a Bug", action: host.reportBug)
                    .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }
    }
}
