# Attaching the App's State to Every Report

Let a sidecar read a snapshot of the app's build and configuration during its session and attach
it to every report.

## Overview

To know which build and configuration a report came from, a sidecar reads the app's state: the
version, build, commit, branch and CI build always, and beside them only what the app registers,
such as its flag and experiment overrides, experiment buckets, environment, a hashed user ID and
values of its own. It is off unless the app enables it. Link `DebugDrawerAppInfo` (`.product(name:
"DebugDrawerAppInfo", package: "DebugDrawer")`), the UI-free half of the App Info plugin, beside the
receiver. Make the snapshot's model with the receiver's sessions and the sources to show, and enable
the capability:

```swift
import DebugDrawerAppInfo
import DebugDrawerReceiver
import Foundation

@MainActor
final class Account {
    var userID: String?
    var plan = "free"
}

@MainActor
final class ProductionAppStateSnapshot {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let appState: DebugDrawerAppState
    let receiver: DebugDrawerReceiver

    init(flags: DebugDrawerFeatureFlagOverrides, account: Account, container: URL) throws {
        appState = DebugDrawerAppState(
            sessions: sessions,
            featureFlags: flags,
            userID: { account.userID },
            values: [DebugDrawerAppStateField("plan") { .string(account.plan) }]
        )
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.featureFlagOverrides(flags))
        receiver.enable(.appState(appState))
        try receiver.start()
    }
}
```

### The risk: low

Whoever holds the sidecar learns which build the app is and how it is configured, and, when the app
registers one, a hashed identifier of the signed-in user. The capability never reads raw user IDs,
tokens or keychain values, and nothing the sidecar sends is executed: its one command,
`DebugDrawerAppState.Command.refresh`, reads the state again.

### Every field beyond the build is the app's choice

With nothing registered, the `DebugDrawerAppState.State` holds only `bundleIdentifier`, `version`,
`build`, `buildMetadata` and `date`. `buildMetadata` is an `AppInfoBuildMetadata`: the commit,
branch and CI build the app passes, or its Info.plist's `DebugDrawerGitCommit`,
`DebugDrawerGitBranch` and `DebugDrawerCIBuildNumber`, as App Info reads them. To add more, pass:

- `featureFlags:` (a `DebugDrawerFeatureFlagOverrides`) for the flags a sidecar overrides now;
- `experiments:` (a `DebugDrawerExperimentOverrides`) for every listed experiment's bucket and
  whether it is forced;
- `environments:` (a `DebugDrawerEnvironments`) for the active backend;
- `userID:` for the hashed user ID;
- `values:` for the app's own, each a `DebugDrawerAppStateField`: a key and a closure returning a
  string, a number or a Boolean (`DebugDrawerAppStateValue`).

The models are the capabilities' own, read as the state is read and followed during a session, so
an override a sidecar sets shows at once. Hand the same model to the receiver, as
`.featureFlagOverrides(flags)` does above.

### Never register a secret

What a field's closure returns leaves the app. Keys aren't checked for what they look like (a key
named `plan` can still be handed a token), so the app decides: no tokens, passwords, keychain values
or raw identifiers of a person. The sidecar's report masks values under the keys its
`DebugDrawerRedaction` masks, as a second line of defense, not the first.

### The user ID is hashed in the app

The closure's raw ID is hashed as it is read, before anything holds it, with HMAC-SHA256 under 32
random bytes the install makes on its first hash. The install keeps that key in the app's own
defaults (`DebugDrawer.AppState.userIDKey`, which Reset App State keeps), never the app group's. The
same user reads the same on every launch of the install, so one install's reports correlate. A
sidecar or a report can't test a guessed ID against the hash without the key, which never leaves
the app, and another install hashes the same user differently. Return `nil` while no one is signed
in.

### Served during a session only

Outside a session the snapshot holds nothing and no closure is asked. Under a grant policy a session
whose grant doesn't list `DebugDrawerAppState.pluginID` is served nothing. The state lives in memory
and in the capability's snapshot file in the app's own directory of the store, which is rewritten
without it as the session ends. Until the app enables `.appState(_:)`, a refresh is refused as
`commandRefused(.unknownCapability)`.

### In bug reports too

`appState.read()` reads the state at any time, so the app's bug reports (<doc:ProductionBugReports>)
carry it: `DebugDrawerBugReports(sessions: sessions) { appState.read() }`.

### In the sidecar

The kit's `DebugDrawerSidecarPlugin.appState` shows the build and each registered field with
Refresh. `DebugDrawerSidecarView` hosts it as soon as the app is reached, so Create Report adds
`App State/app-state.json` to every report, whether the plugin was opened or not.
