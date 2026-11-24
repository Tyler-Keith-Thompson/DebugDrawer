# Overriding Feature Flags in Production

Let an employee's sidecar override the flags the app lists, on their own device, for a session.

## Overview

`enable(.featureFlagOverrides(adapter))` serves a sidecar the flags the app's
`DebugDrawerFeatureFlagAdapter` lists. <doc:ProductionBuilds> shows an adapter and a receiver that
enables it.

### The risk

An employee holding the sidecar can turn on, on their own device, a feature that hasn't been
released. An override changes only what the app reads through the adapter, so a flag the server
enforces (an entitlement it checks, content it serves only when the flag is on) stays enforced by
the server.

### Only the flags the app lists

The capability is off until the app calls `enable(.featureFlagOverrides(adapter))`. The app marks
which flags an employee may override by listing them, and only them, in the adapter's
`overridableFlags()`. A command for any other flag is refused as `commandRefused(.notExposed)`, and
one with a value of another kind than the flag's as `commandRefused(.malformedCommand)`. Neither
reaches the adapter.

### Audit and delivery

Each override and each clear is audited as `commandApplied`, and the session's revert as
`changeReverted`. A command the sidecar leaves while the app is in the background is applied as the
app comes to the foreground.

### Scope and relaunches

With the default scope the overrides are cleared as the session ends or expires. Overrides a
session left because the app quit during it are cleared as the next launch makes the capability, so
make it at startup. With `scope: .persistent` they stay until a sidecar clears them, across
launches when the adapter keeps its overrides.

`DebugDrawerFeatureFlagOverrides` keeps the keys it overrode (never their values) in the standard
defaults, or in those passed to `init(adapter:defaults:)`, so a relaunched app still lists and
clears them.
