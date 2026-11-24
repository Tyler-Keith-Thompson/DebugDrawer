# A Device Lab: Sidecars Sharing Their Sessions with a Mac

Drive production builds on many devices from one Mac: each device's sidecar relays the session it
opens to a Mac viewer over the local network.

## Overview

A QA lab can drive production builds on many devices from one Mac. Each device's sidecar relays
what it reaches of the app picked to a viewer on the Mac, over the local network, and carries the
viewer's commands back. The production app's receiver still talks over the app group alone and
opens no listener; a test checks its binary for Network.framework and listener symbols and finds
none. Turn the relay on with one modifier on the kit's view:

```swift
DebugDrawerSidecarView(groupIdentifier: "TEAMID.com.example.debug", plugins: [.featureFlagOverrides, .tweaks])
    .debugDrawerSidecarRelay()
```

Each app's screen then has a Mac Viewer control. Start Serving listens; `startsServing: true`
listens as soon as an app is picked, for a lab device whose sidecar always shares. Each Mac asking
to pair shows with its six-digit code and Reject, and each paired Mac with Disconnect, as Remote
Viewing shows them in a drawer (the Remote documentation's Remote Viewing article). Without the
modifier nothing listens.

The relay itself is public, for a layout of your own: `DebugDrawerSidecarRelay(connection:configuration:)`
over a `DebugDrawerSidecarConnection`, with `start()`, `stop()`, its `server` (whose
`pairingRequests` hold the codes to show) and its `snapshot`.

### What the relay shares, and when

The relay shares only within the session the sidecar's person opens. While no session is open in
the app, it serves nothing but its own snapshot. As a session opens, it serves each capability the
app serves that the session may read, under the capability's own ID, once the app's first snapshot
of that capability arrives. Under a grant policy, that is only what the grant lists, which is the
receiver's own rule for what it writes to the store.

When the session ends, reaches its expiry date (even while the suspended app hasn't ended it
yet), or serving stops, the relay drops every capability and closes the transport that read them.
So a viewer is never served anything the session can no longer read, and the next session starts
afresh.

Commands go back as the sidecar's own. The receiver applies or refuses each one within the session
and its grant, and audits it, exactly as if the sidecar had sent it. The relay adds no gate and
widens none. The sessions themselves aren't relayed, so a viewer can't open or end a session or
read its grant.

### Viewing a relayed app

A viewer pairs as it would with any `DebugDrawerNetworkServer` and reads
`DebugDrawerSidecarRelay.Snapshot` under `DebugDrawerSidecarRelay.pluginID`: the app,
`sessionExpires`, and the `pluginIDs` shared now. It draws each shared capability with the kit's
own plugin over the paired transport, through `plugin(over:)`:

```swift
@MainActor
func showFlags(of viewer: DebugDrawerNetworkTransport) async throws -> AnyDebugDrawerPlugin? {
    let relay = try await viewer.connect(
        toPlugin: DebugDrawerSidecarRelay.pluginID, snapshot: DebugDrawerSidecarRelay.Snapshot.self, command: Never.self
    )
    guard relay.snapshot.pluginIDs.contains(DebugDrawerFeatureFlagOverrides.pluginID) else { return nil }
    return try await DebugDrawerSidecarPlugin.featureFlagOverrides.plugin(over: viewer)
}
```

### Info.plist and entitlements

A sandboxed Mac sidecar needs the `com.apple.security.network.server` entitlement. On iOS the
sidecar app, not the production app, declares the service it advertises:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Shares the app you pick with a Mac in your lab, once you pair it with a code.</string>
<key>NSBonjourServices</key>
<array>
    <string>_debugdrawer._tcp</string>
</array>
```

### Security

The Mac viewer is a new party to the session. The person holding the sidecar pairs it with the
code, and the traffic between them is not encrypted, so share on a network you trust. The
Receiver documentation's Security Model and Distribution article has the details.

The relay is part of the kit on iOS, iPadOS and macOS. watchOS has no network transport, so a
watch sidecar doesn't relay.

### In the examples

`Example/Sidecar` carries the modifier. `-ShareWithMac` starts serving as an app is picked,
`-RemoteViewersOnLoopback` listens on 127.0.0.1 alone, and `-MacViewerPort <port>` listens on a
fixed port. The macOS example's Remote window (Debug > Remote Viewer) shows a relayed app: once
paired, it lists the capabilities the session shares and draws each with the kit's plugin, live,
until the session ends.
