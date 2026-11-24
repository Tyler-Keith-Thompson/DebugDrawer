# Raising Log Levels in Production

Let a sidecar raise chosen subsystems of the app's own logger to a verbose level for its session,
while an employee reproduces a problem on a release build.

## Overview

An app can't change the level unified logging (os_log) keeps for its subsystems, but its own
logger can, so the hook is the app's. `enable(.logLevels(adapter))` serves a sidecar the subsystems
the app's `DebugDrawerLogLevelAdapter` lists in `elevatableSubsystems()`. Each is a
`DebugDrawerLogSubsystem` with the levels a sidecar may set (the logger's own names, such as
`"info"`, `"debug"`, `"trace"`) and the level it logs at now.

Within a session the sidecar sets one (`DebugDrawerLogLevels.Command.setLevel(subsystem:level:)`),
and the receiver calls the adapter's `setLevel(_:forSubsystem:)`. `reset(subsystem:)` and
`resetAll` call `resetLevel(forSubsystem:)` for the subsystems the sidecar raised, never one the
app raised itself.

### The risk: personal data in verbose lines

Verbose levels log more of what the app handles. The capability captures no log line and sends
none to the sidecar. The raised lines go where the app's logger already writes them, through the
redaction it applies to every line (os_log's `privacy: .private` interpolations, a swift-log
handler that masks fields), so keep that redaction on at the verbose levels too.

To read the lines from the sidecar, forward them to a diagnostics capture as well
(<doc:DiagnosticsCapture>), which redacts them itself. In a debug build, a logger bridged to the
Console through `ConsoleLogSink` shows the raised lines in the drawer as logged.

### Off by default, and only what the app lists

Until the app enables the capability, a command to it is refused as
`commandRefused(.unknownCapability)`, even inside a session. A subsystem the adapter doesn't list
is refused as `commandRefused(.notExposed)`, and a level the subsystem doesn't list as
`commandRefused(.malformedCommand)`. Neither reaches the adapter. Each change is audited as
`commandApplied`.

### For the session, always

As the session ends, expires (at the sessions' maximum duration or the grant's expiry) or a gate
turns it off, the adapter is told to reset each subsystem the sidecar raised, audited as
`changeReverted`. There is no persistent scope.

`DebugDrawerLogLevels` keeps the names of the subsystems it raised (never their levels) in the
standard defaults, or in those passed to `init(adapter:defaults:)`. Levels a session left when the
app quit or was killed are then reset as the next launch makes the capability, so make it at
startup.
