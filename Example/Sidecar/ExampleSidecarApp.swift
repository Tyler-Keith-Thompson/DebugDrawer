import DebugDrawerSidecarKit
import SwiftUI

// A company's sidecar app, built from the kit: it lists the apps in the example's app group that
// serve a sidecar (the iOS example's debug build, through its store and socket; a production app
// through its receiver), opens their sessions, shows their Console and Network, and makes a report
// of what it shows. Everything else the company would add (sign-in, a grant from its server, its
// branding) goes around DebugDrawerSidecarView or into its grant closure.

@main
struct ExampleSidecarApp: App {
    var body: some Scene {
        WindowGroup {
            DebugDrawerSidecarView(groupIdentifier: "group.com.debugdrawer.example")
        }
    }
}
