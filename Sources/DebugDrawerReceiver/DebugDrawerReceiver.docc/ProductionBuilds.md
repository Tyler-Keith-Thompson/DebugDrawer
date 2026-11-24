# Serving a Sidecar from a Production Build

Link the receiver into a release build so an employee-only sidecar app can reach the app, for the
capabilities the app enables and only within sessions the sidecar opens.

## Overview

A release build gets none of the drawer. To let an employee-only sidecar app reach a production
app, the app links one more product, `DebugDrawerReceiver`. It has no UI, no interception, no
plugin and no dependency on the drawer. The receiver serves a sidecar, over the app group's
store, only the capabilities the app enables, within sessions the sidecar opens, and refuses
everything else.

Some capabilities live in UI-free modules the app links beside the receiver:

| To | Link |
|---|---|
| Offer tweaks | `DebugDrawerTweaks` |
| Mirror analytics events | `DebugDrawerAnalytics` |
| Serve translators and accessibility reviewers | `DebugDrawerLocalization` and `DebugDrawerAccessibility` |
| Forward crash reports and MetricKit payloads | `DebugDrawerMetricKit` |
| Mock responses for a session | `DebugDrawerNetwork` |
| Show the push token for test pushes | `DebugDrawerNotifications` |
| Record hangs and signposts | `DebugDrawerHangDetector` |
| Spoof the location for a session | `DebugDrawerLocation` |
| Show a snapshot of the app's state | `DebugDrawerAppInfo` |

Each capability is described in an article of its own, listed on the module's page.

Before shipping the receiver, read <doc:SecurityModel>. It says what the receiver trusts (the
team's signature and the app group, on iOS and on the Mac), what someone holding the sidecar can
do with each capability, how to distribute the sidecar (TestFlight internal testers or a private
Apple Business Manager app, never an Enterprise account or a public TestFlight link), and what to
tell App Review.

```swift
import DebugDrawerReceiver

@MainActor
final class FlagServiceAdapter: DebugDrawerFeatureFlagAdapter {
    private(set) var overrides: [String: DebugDrawerFeatureFlagValue] = [:]

    func overridableFlags() -> [DebugDrawerFeatureFlag] {
        [DebugDrawerFeatureFlag(key: "new-checkout", value: overrides["new-checkout"] ?? .bool(false))]
    }

    func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {
        overrides[key] = value
    }

    func clearOverride(forKey key: String) {
        overrides[key] = nil
    }
}

@MainActor
final class ProductionReceiver {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(flags: FlagServiceAdapter, container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.featureFlagOverrides(flags))
        try receiver.start()
    }
}
```

### Linking and the store

Add the receiver to the production target alone (`.product(name: "DebugDrawerReceiver", package:
"DebugDrawer")`); the drawer and its plugins stay in the debug configuration. `container` is the
app group's container, `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`,
which the sidecar app shares.

The receiver keeps to the app's own directory of that store, `DebugDrawer/apps/<bundle ID>/`
(`receiver.appDirectory`), named by the main bundle's identifier. Several apps of a company can
therefore share one group and one sidecar, as the "Several apps, one sidecar" section of the
Sidecar Kit documentation's Building a Sidecar App article describes. The sidecar reaches the
receiver with a `DebugDrawerSidecarTransport` (or a `DebugDrawerAppGroupStoreTransport`) on that
app's directory
(`DebugDrawerAppGroupContainer.appDirectory(of:)`), opens a session through
`DebugDrawerSessions.pluginID`, then connects to `DebugDrawerFeatureFlagOverrides.pluginID`. The
receiver serves the store only, not the socket.

### Nothing until enabled

With no capability enabled, every command is refused, opening a session included. A command to an
ID the app didn't enable, or disabled with `disable(_:)`, is refused even inside an open session.
Each refusal is logged and written to the sessions' audit log
(`commandRefused(.unknownCapability)`).

### Capabilities are models

`.featureFlagOverrides(adapter)` overrides the flags the adapter lists, and only with a value of
the kind the flag has. `.experimentOverrides(adapter)` forces the experiments it lists into one of
their variants (<doc:ExperimentOverrides>), and `.logLevels(adapter)` raises the log subsystems it
lists (<doc:LogLevels>). `clearAllOverrides` clears only the overrides it set, never the app's
own. `.model(_:id:scope:)` serves any `DebugDrawerPluginModel` of the app's.

A command decodes into the model's own `Command` type or is refused as malformed. Nothing received
is run or evaluated. A sidecar reads only the model's snapshot, so list nothing secret in it.

### Served only within a session

Every app of the group can read the store, so a capability's snapshot is in it only while a
session is open. Outside one, the app's directory holds its presence file and the sessions'
snapshot, and nothing a capability holds.

As a session opens, each capability's snapshot is written before the sessions' snapshot says it is
open, so a sidecar connects to a capability once it sees its session (until then its transport's
`connect` waits). Each snapshot leaves the store as the session ends or expires, a gate turns off,
the capability is disabled or the receiver stops. `start()` first removes whatever a launch that
was killed during a session left behind.

Under a grant policy, and for a capability made `requiringGrant()`, a session reads only the
capabilities its grant lists (<doc:SignedGrants>). While a session is open the group's other apps
can read what it reads, so list nothing secret.

### Scopes

Each capability takes a `DebugDrawerChangeScope`. `.session(revertWith:)` reverts it as the
session ends or expires (feature flag overrides default to `.session(revertWith:
.clearAllOverrides)`), and `.persistent` keeps it.

### Reverted after a kill too

Sessions live in memory, so a session in which the app quit or was killed never ends. The receiver
keeps a record in the app's directory of the store, `unreverted-changes.json`, of each
session-scoped capability a session changed. The record is written before the change is applied
and cleared once the change is reverted. As the next launch enables that capability, before or
after `start()`, the receiver performs the scope's command and audits it as `changeReverted` in the
session that made the change. A capability the next launch doesn't enable keeps its record until a
launch does.

The shipped capabilities whose state outlives the process keep a record of their own beside the
change and revert it as they are made (each capability's article says how), so make every
capability at startup.

### The app draws the indicator

Observe `sessions.snapshot`, as the Sidecar Kit documentation's Sidecar Sessions article shows,
and draw the session indicator in the app.

### In a debug build

In a debug build the receiver runs beside the drawer. Show the same model in a plugin through
`DebugDrawerPluginTransport.direct(to:)`, and pass it to `.featureFlagOverrides(_:)` or
`.model(_:id:scope:)`, so the app's own drawer shows what a sidecar does. `DebugDrawer` re-exports
the receiver's module. Keep the receiver's store directory apart from a debug
`DebugDrawerAppGroupStoreServer`'s, as both perform the commands left there.
