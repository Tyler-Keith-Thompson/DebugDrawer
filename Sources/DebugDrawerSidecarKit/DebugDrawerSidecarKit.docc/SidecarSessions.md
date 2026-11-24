# Sidecar Sessions

Act on a sidecar's commands only while someone is debugging: within a session the sidecar opens,
which expires, reverts what it changed and leaves an audit log.

## Overview

A registry made with `DebugDrawerSessions` acts on a sidecar's commands only within a session the
sidecar opens. A session expires at most the host's maximum duration after it opens. Ending it, or
its expiry, reverts the changes the host declared session-scoped and keeps the persistent ones.
Every command is written to an audit log, which the host reads and forwards.

### Registering models with a change scope

Each capability's model is registered with a `DebugDrawerChangeScope`. `.session(revertWith:)`
names the command that puts the model back, and `.persistent` keeps its changes. A model
registered without a scope serves its snapshots, and its commands are refused.

```swift
@MainActor
final class SidecarReceiver {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let registry: DebugDrawerModelRegistry
    let server: DebugDrawerAppGroupStoreServer
    private var forwarding: AnyCancellable?

    init(logLevels: LogLevelsModel, flags: FlagOverridesModel, container: URL) throws {
        registry = DebugDrawerModelRegistry(sessions: sessions)
        registry.register(logLevels, id: "MyApp.LogLevels", scope: .session(revertWith: .reset))
        registry.register(flags, id: "MyApp.FlagOverrides", scope: .persistent)
        server = DebugDrawerAppGroupStoreServer(registry: registry, directory: container.appending(path: "DebugDrawer"))
        forwarding = sessions.auditEntries.sink { entry in
            AuditForwarder.send(entry)
        }
        try server.start()
    }
}
```

### Showing that a session is active

The library draws no indicator. `sessions.snapshot` is a `DebugDrawerSessionState`, published as
it changes, and the app shows its own indicator, in its own style, for as long as a session is
active, so the person holding the device always knows debug tooling is engaged:

```swift
struct SessionIndicator: View {
    @ObservedObject var sessions: DebugDrawerSessions

    var body: some View {
        if let session = sessions.snapshot.session {
            HStack {
                Text("Debug session until \(session.expires, style: .time)")
                Button("End") { sessions.end() }
            }
        }
    }
}
```

### Opening and ending a session

A sidecar opens a session by connecting to `DebugDrawerSessions.pluginID` like any plugin, with
`DebugDrawerSessionState` snapshots and `DebugDrawerSessionCommand` commands, and sending
`.open(duration:)`. It ends the session with `.end`.

The app refuses a command, and changes nothing, when it arrives while no session is open, after
the session ended or expired, for a model registered without a scope, or for no model at all. This
holds over the socket and the store alike. A refusal is final. The app still acknowledges the
command, so `DebugDrawerSidecarTransport` doesn't send it again when it switches channels; the
sidecar sends it anew once a session is open.

A session asked to last longer than the maximum expires at the maximum. A request to open a
session while another is open is refused. Expiry is a one-shot timer set for the expiry date. If a
command arrives after that date but before a suspended app's timer has fired, the session expires
first. The app's own drawer, in the same process, isn't subject to sessions.

### The audit log

Each `DebugDrawerAuditEntry` holds its date, the session's ID, the capability and the event. The
capability is the ID the model was registered under, or `DebugDrawerSessions.pluginID` for a
session opening or ending. The event is one of:

- `sessionOpened(expires:grant:)`
- `sessionEnded`, with `.ended`, `.expired`, or `.disabledByHost` as a receiver's gate turns off
- `commandApplied`
- `commandRefused`, with its reason
- `changeReverted`

An entry never holds what a command carried. It is `Codable`, for forwarding as JSON. `auditLog`
keeps the newest 1,000 entries in memory (`auditCapacity` sets another bound), and `auditEntries`
publishes every entry as it is recorded.

The sessions are real in every build, because the receiver uses them (the Receiver documentation's
Serving a Sidecar from a Production Build article). In a release build the drawer's registry and servers are stand-ins that never reach
the sessions, so only a `DebugDrawerReceiver` opens one there.
