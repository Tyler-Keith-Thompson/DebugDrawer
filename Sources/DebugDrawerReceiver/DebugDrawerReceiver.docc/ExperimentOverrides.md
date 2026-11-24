# Overriding Experiments in Production

Let employees see each arm of an A/B test on a release build, and keep their devices out of the
experiment's analysis while they do.

## Overview

`enable(.experimentOverrides(adapter))` serves a sidecar the experiments the app's
`DebugDrawerExperimentAdapter` lists in `overridableExperiments()`, each with its variants and the
variant the app is assigned now (`DebugDrawerExperiment`). Within a session the sidecar forces one
of those variants (`DebugDrawerExperimentOverrides.Command.setOverride(experiment:variant:)`).

### The risk, and the exclusion hook

A forced variant isn't a real assignment, so the device's events would pollute the experiment's
data. The exclusion hook guards against it. The adapter must implement
`overriddenExperimentsDidChange(_:)`, which hears the overridden experiments' keys as the model is
made (overrides kept from the last launch included) and at every change, and hears an empty set
once none is left. While it holds any, leave the session or user out of the experiments' analysis.

`DebugDrawerExperimentOverrides.isExcludedFromAnalytics` and `overriddenExperiments` say the same
at any time, from any thread, for an analytics pipeline that tags events on its own queue. In that
case make the model yourself, then call `enable(.experimentOverrides(model))`.

### Only what the app lists

The capability is off until the app enables it: a command to it before then is refused as
`commandRefused(.unknownCapability)`, even inside a session. An experiment the adapter doesn't list
is refused as `commandRefused(.notExposed)`, and a variant the experiment doesn't have as
`commandRefused(.malformedCommand)`. Neither reaches the adapter.

### Audit, scope and relaunches

Audit, foreground delivery, scopes and the keys kept across launches work as they do for feature
flag overrides (<doc:FeatureFlagOverrides>). By default the overrides are cleared, and the
exclusion lifted, as the session ends. With `scope: .persistent` the device stays excluded across
launches until a sidecar clears the overrides.
