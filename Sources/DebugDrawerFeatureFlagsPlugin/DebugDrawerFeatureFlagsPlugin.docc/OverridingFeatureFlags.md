# Overriding Feature Flags

Show the app's flags with their live values, and override any of them on this device.

## Overview

The Feature Flags plugin shows every flag the app's flag service serves, with its live value, and
overrides any of them on this device. It knows no vendor. The app adapts its service
(LaunchDarkly, Firebase Remote Config, Statsig or its own) to `FeatureFlagProvider`, which lists
the flags, says what the app reads for one, and applies and clears an override. A flag's value is
a Boolean, a number or a string:

```swift
import DebugDrawerFeatureFlagsPlugin

/// The app's own flag service, adapted for the drawer: live values from the server, and overrides
/// that win over them.
final class AppFlags: FeatureFlagProvider {
    var live: [String: FeatureFlagValue] = ["new-checkout": .bool(false), "discount": .number(0.1)]
    private var overrides: [String: FeatureFlagValue] = [:]

    func flags() -> [FeatureFlag] {
        live.sorted { $0.key < $1.key }.map { FeatureFlag(key: $0.key, liveValue: $0.value) }
    }

    func currentValue(forKey key: String) -> FeatureFlagValue? {
        overrides[key] ?? live[key]
    }

    func setOverride(_ value: FeatureFlagValue, forKey key: String) {
        overrides[key] = value
    }

    func clearOverride(forKey key: String) {
        overrides[key] = nil
    }
}

let appFlags = AppFlags()

DebugDrawer.shared.installFeatureFlags(provider: appFlags)

// Anywhere in the app, through the adapter, so overrides apply:
let isNewCheckout = appFlags.currentValue(forKey: "new-checkout") == .bool(true)
```

### Adapting a vendor SDK

An adapter over a vendor SDK maps the SDK's flags to `FeatureFlag`s. It answers
`currentValue(forKey:)` with the override it holds, if any, before asking the SDK. Where the SDK
has local overrides of its own, `setOverride` and `clearOverride` call them.

### Where overrides are kept

The plugin keeps the overrides. They persist across launches in the standard `UserDefaults`, under
`com.debugdrawer.featureFlags.overrides`, and `installFeatureFlags` applies each one to the
adapter again before it returns, so an adapter can hold overrides in memory. To keep them
elsewhere, pass `installFeatureFlags(provider:storage:)` a `UserDefaultsFeatureFlagOverrideStorage`
with other defaults or another key, or a `FeatureFlagOverrideStorage` of your own.

### In the drawer

The drawer lists the flags, with a search over their keys and titles and an Overridden only
switch. A Boolean flag has a switch; a number or string flag has a field. An overridden flag has a
button that clears its override, and Reset All clears every override. The drawer reads the
adapter again each time it shows the plugin and when Refresh is pressed.

### Release builds

`FeatureFlagProvider`, `FeatureFlag`, `FeatureFlagValue` and the storage types exist in every
configuration, so an adapter compiles in release. There nothing calls it, and the app reads its
service's live values.
