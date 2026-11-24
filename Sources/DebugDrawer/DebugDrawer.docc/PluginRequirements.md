# What the Plugins Need from the App

The entitlements and Info.plist keys some shipped plugins read, and how much each plugin keeps in
memory.

## Overview

No plugin needs an Info.plist key or an entitlement to install. Some of what they show depends on
the app's own:

| Plugin | Needs |
|---|---|
| Notifications | The `aps-environment` entitlement and a call to `registerForRemoteNotifications()` for a device token; on the Mac the entitlement needs a provisioning profile |
| Background Tasks | `BGTaskSchedulerPermittedIdentifiers`, and `UIBackgroundModes` with `fetch` for app refresh or `processing` for processing tasks |
| Permissions | The usage descriptions it lists; a request names a key the Info.plist lacks |
| Keychain, Reset App State | On the Mac, a signed `application-identifier` or `keychain-access-groups` entitlement for the data protection keychain; without one the plugin shows `errSecMissingEntitlement` |
| File Browser, UserDefaults, Databases, Reset App State | An app group in `com.apple.security.application-groups` for its container or suite; Databases and Reset App State find the app's groups on their own |
| Location | Nothing: a spoofed location is delivered whether or not the app is authorized |

### Memory limits

The lists the plugins keep in memory have these limits:

| Plugin | Keeps | Set with |
|---|---|---|
| Console | The newest 2,000 lines | `ConsoleLogStore.shared.capacity` |
| Network | The newest 200 requests, 1 MB of each request and response body, 50 WebSocket connections of 500 frames | `NetworkStore.shared.capacity`, `installNetwork(bodyLimit:)` |
| Disk I/O | The newest 500 calls | `DiskIOStore.shared.capacity` |
| Analytics | The newest 1,000 events | `AnalyticsEvents.install(capacity:)` |
| Screen Recording | The newest 5 recordings | `ScreenRecording.install(capacity:)` |
| Crash Reports | The newest 10 reports | Fixed |
| Hangs | The newest 50 hangs | Fixed |
| MetricKit | The newest 50 payloads | Fixed |

Console and Network also keep 5 earlier launches, in at most 20 MB, set when they are installed.
The Console plugin's Console Sessions article and the Network plugin's Network Sessions article
cover them.
