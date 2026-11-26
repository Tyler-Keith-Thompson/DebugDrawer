# Switching Backend Environments in Production

Point a production build at a staging or canary backend the app allowlists, for a sidecar's
session, to dogfood it there.

## Overview

The capability is off unless the app enables it. It is high risk, so the allowlist is mandatory and
is all a sidecar can pick from. The app lists its environments, each an ID, a title and a summary,
and maps the ID to its own configuration in an adapter:

```swift
import CryptoKit
import DebugDrawerReceiver
import Foundation
import SwiftUI

@MainActor
final class BackendSwitcher: DebugDrawerEnvironmentAdapter {
    private(set) var baseURL = "https://api.example.com"

    func activate(_ environment: DebugDrawerEnvironment) {
        switch environment.id {
        case "staging": baseURL = "https://staging.api.example.com"
        case "canary": baseURL = "https://canary.api.example.com"
        default: baseURL = "https://api.example.com"
        }
    }
}

@MainActor
final class ProductionEnvironments {
    let sessions: DebugDrawerSessions
    let environments: DebugDrawerEnvironments
    let receiver: DebugDrawerReceiver

    init(grantServerKey: Curve25519.Signing.PublicKey, backend: BackendSwitcher, container: URL) throws {
        sessions = DebugDrawerSessions(maximumDuration: 15 * 60, grantPolicy: DebugDrawerGrantPolicy(
            verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(grantServerKey)]),
            audience: "com.example.MyApp"
        ))
        environments = try DebugDrawerEnvironments(
            default: DebugDrawerEnvironment("production", title: "Production"),
            allowing: DebugDrawerEnvironment("staging", title: "Staging", summary: "Yesterday's server build"),
            DebugDrawerEnvironment("canary", title: "Canary"),
            adapter: backend
        )
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.environments(environments))
        try receiver.start()
    }
}

struct EnvironmentIndicator: View {
    @ObservedObject var environments: DebugDrawerEnvironments

    var body: some View {
        let snapshot = environments.snapshot
        if snapshot.isSwitched, let active = snapshot.environments.first(where: { $0.id == snapshot.activeEnvironment }) {
            Label("Backend: \(active.title)", systemImage: "server.rack")
        }
    }
}
```

### The risk: high

Whoever holds the sidecar, a leaked copy included, can send the app's traffic, and the signed-in
account's credentials with it, to another backend. Only a backend the app lists can be chosen, so
the worst a leak does is point the app at your own staging.

### The allowlist is mandatory and holds no URL

`DebugDrawerEnvironments` and `.environments(default:allowing:_:adapter:)` take the default and at
least one allowed environment as separate parameters, so an empty allowlist doesn't compile. They
throw `DebugDrawerEnvironments.InvalidEnvironments` for an allowed environment repeating another's
ID (the default's included) and for an empty ID.
Write the list in the app's source, not from remote configuration, which a leak would target next.

A `DebugDrawerEnvironment` has an ID, a title and a summary and nothing else. Base URLs, hosts and
keys stay in the adapter, and no command or snapshot has a field an address could travel in.

### Only by ID, only listed ones

The sidecar connects to `DebugDrawerEnvironments.pluginID` with `DebugDrawerEnvironments.Snapshot`
(the environments, the default's ID and the active one's) and `DebugDrawerEnvironments.Command`:
`activate(environment:)`, with an ID, and `reset`. An ID the app didn't list (an address among them)
is refused as `commandRefused(.notExposed)` and changes nothing. The adapter is handed the app's own
`DebugDrawerEnvironment`, never one decoded from the sidecar. Until the app enables
`.environments(_:)`, a switch is refused as `commandRefused(.unknownCapability)`, even inside a
session.

### A grant when a verifier is configured

With a `DebugDrawerGrantPolicy` on the sessions, as above, a switch needs a session whose grant
lists `DebugDrawerEnvironments.pluginID`. Without a grant no session opens, and a grant for other
capabilities is refused as `commandRefused(.capabilityNotGranted)`. Grants stay optional: without a
policy a switch needs only a session. Add `.requiringGrant()` to the capability to refuse switches
as `commandRefused(.grantMissing)` in any session without one. <doc:SignedGrants> describes grants.

### For the session, always

As the session ends, expires or the receiver's or the capability's gate turns off, the adapter is
told to activate the default, audited as `changeReverted`. The environment a session switched to is
recorded in the defaults before the adapter is told, so when the app is killed during a session the
next launch activates the default as it makes the capability. Make the capability as the app
starts, before the first request, and keep the switch itself in memory in the adapter.

### The app shows it

`environments.snapshot.isSwitched` is `true` while the app is pointed anywhere but its default,
which only happens during a session. Show the backend in the session indicator, as
`EnvironmentIndicator` does, so the person holding the device knows their traffic isn't going to
production.

### In the sidecar

The kit's `DebugDrawerSidecarPlugin.environments` lists the environments under a high-risk warning,
with the active one marked, Switch for each other one, and Reset to Default.
