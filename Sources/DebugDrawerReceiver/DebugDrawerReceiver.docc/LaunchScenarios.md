# Launching the App into a State with Scenarios

Reach a screen deep in a release build from the sidecar without tapping through the app to get
there.

## Overview

To open a state such as "open order 123", "show the paywall" or "onboarding step 3", the app
registers named scenarios. Each has the parameters it takes and a handler of its own that puts the
app there. The sidecar lists them, with a field for each parameter, and Launch brings the app to the
foreground and runs the handler:

```swift
@MainActor
final class ShopRouter {
    private(set) var screen = "Home"

    func openOrder(_ id: Int) { screen = "Order \(id)" }
    func showPaywall(plan: String) { screen = "Paywall (\(plan))" }
}

@MainActor
final class ProductionScenarios {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(router: ShopRouter, container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.scenarios([
            DebugDrawerScenario("open-order", title: "Open Order", parameters: [
                .integer("orderID", title: "Order", default: 123, in: 1 ... 999_999)
            ]) { arguments in
                router.openOrder(arguments.integer("orderID") ?? 123)
            },
            DebugDrawerScenario("show-paywall", title: "Show Paywall", parameters: [
                .choice("plan", title: "Plan", options: ["monthly", "annual"])
            ]) { arguments in
                router.showPaywall(plan: arguments.string("plan") ?? "monthly")
            }
        ], launchURL: URL(string: "shop-internal://")))
        try receiver.start()
    }
}
```

### The risk: whatever the handlers allow

An employee holding the sidecar can put their own device in any state a registered scenario
reaches, with any value its parameters take. Register only scenarios fit for production, bound each
parameter tightly, keep the server's own checks where a handler reaches the server, and add
`.requiringGrant()` to the capability when team signing alone isn't enough.

### Off by default, and only what the app declares

Until the app enables `.scenarios(_:)`, a launch is refused as `commandRefused(.unknownCapability)`,
even inside a session. The receiver passes a handler only a registered scenario's ID and values for
the parameters that scenario declares (`DebugDrawerScenarioParameter`: `.string(_:maximumLength:)`,
`.integer(_:in:)`, `.boolean(_:)`, `.choice(_:options:)`), each checked against its kind and bounds,
and evaluates nothing it receives.

A scenario the app didn't register is refused as `commandRefused(.notExposed)`. A parameter the
scenario doesn't declare, or a value of another kind, outside the range, longer than the maximum or
not among the options, is refused as `commandRefused(.malformedCommand)`. Neither runs a handler. A
declared parameter the launch leaves out takes its default. The handler reads the values typed:
`arguments.integer("orderID")`, `string(_:)`, `boolean(_:)`.

### Within a session, audited, and not reverted

A launch is performed only in an open session and audited as `commandApplied`;
`DebugDrawerScenarios.Snapshot.lastRun` tells the sidecar it ran. What a handler did lasts past the
session, as the library can't undo it.

### Bringing the app forward

The sidecar opens `launchURL`, a URL of the app's own scheme (`CFBundleURLTypes`), to bring the app
to the foreground; on the Mac it opens the app by its bundle identifier instead. The receiver
doesn't depend on that URL. The launch waits in the store and is performed as the app comes to the
foreground, however it got there, or at once when the app is already there. Handling the URL is up
to the app, which needn't do anything with it.

### In the sidecar

The kit's `DebugDrawerSidecarPlugin.scenarios` lists the scenarios with a field for each parameter
(a text field, a number field, a switch or a picker) and a Launch button, which sends the launch and
then opens the app (`DebugDrawerSidecarApp.open(url:)`).
