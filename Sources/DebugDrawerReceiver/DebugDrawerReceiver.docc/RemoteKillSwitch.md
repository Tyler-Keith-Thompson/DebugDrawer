# Turning the Receiver Off Remotely

Shut every sidecar out without a release, or turn off one capability, from your own remote
configuration.

## Overview

For a leaked sidecar app, say, give the receiver a gate backed by your own remote configuration,
and give a capability one of its own. The library calls no configuration service itself;
`RemoteConfig` here stands for yours:

```swift
@MainActor
final class GatedReceiver {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(config: RemoteConfig, flags: FlagServiceAdapter, container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions) {
            config.bool("sidecar_enabled")
        }
        receiver.enable(.featureFlagOverrides(flags)) { config.bool("sidecar_flag_overrides") }
        config.onUpdate { [receiver] in receiver.reevaluateGates() }
        try receiver.start()
    }
}
```

### The receiver's gate first

`isAllowed` (set at `init(directory:sessions:isAllowed:)` or later) is asked before anything else at
every command, a session's opening included, and so before any grant is verified. While it returns
`false`:

- every command is refused as `commandRefused(.receiverDisabled)`;
- the open session ends as `sessionEnded(.disabledByHost)`, reverting its session-scoped changes;
- no capability's snapshot is written, and each one's file leaves the store.

The sessions' snapshot stays, so the sidecar sees its session end.

### A capability's gate

`enable(_:isAllowed:)` gates one capability. While its gate returns `false`, that capability's
commands are refused as `commandRefused(.capabilityDisabled)`, its snapshot leaves the store, and
its session-scoped change in the open session is reverted at once (`changeReverted`). The session
and the other capabilities carry on.

### When it takes effect

A closure can't announce a change, so the receiver asks the gates at each command, as it starts, as
the app comes to the foreground and before writing a snapshot. Call `reevaluateGates()` as your
configuration updates, as above, to end an open session at once without waiting for a command. A
gate turned back on serves the snapshots again, and a new session can open. Nothing polls.
