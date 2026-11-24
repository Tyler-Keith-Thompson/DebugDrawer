# Showing the Push Token for Test Pushes

Show a sidecar the device's APNs token, which APNs server it belongs to, and whether the app may
show notifications, so an employee can aim a test push at their own device.

## Overview

The app can show a sidecar all three during its session. It is off unless the app enables it. Link
`DebugDrawerNotifications` (`.product(name: "DebugDrawerNotifications", package: "DebugDrawer")`),
the UI-free half of the Notifications plugin, beside the receiver. Make the mirror with the
receiver's sessions, enable the capability, and hand the mirror the token from the app delegate:

```swift
import DebugDrawerNotifications
import DebugDrawerReceiver
import Foundation

@MainActor
final class ProductionPush {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver
    let pushRegistration: PushRegistrationMirror

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        pushRegistration = PushRegistrationMirror(sessions: sessions)
        receiver.enable(.pushRegistration(pushRegistration))
        try receiver.start()
    }

    /// From application(_:didRegisterForRemoteNotificationsWithDeviceToken:).
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        pushRegistration.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
    }
}
```

### What the sidecar sees

The sidecar connects to `PushRegistrationMirror.pluginID`. The `PushRegistrationMirror.Snapshot`
holds:

- the open session's ID;
- the `registration`: `.registered(deviceToken:)` as lowercase hexadecimal, the form push tools
  take, `.failed(message:)` from `didFailToRegisterForRemoteNotifications(withError:)`, or
  `.notRegistered`;
- the `environment`, a `PushEnvironment`: the `server`, `.production` or `.sandbox`, and its
  `source`;
- the `settings`: the authorization status (Allowed, Denied, Provisional, Not Asked) and each
  presentation setting, read from User Notifications as the session opens and again on
  `PushRegistrationMirror.Command.refresh`.

The app can't fetch a token itself; only the delegate hears it. The app registers for remote
notifications as it does today and passes the token on.

### The environment

`PushEnvironment.detected()`, the default, reads the app's signature: on the Mac the
`com.apple.developer.aps-environment` entitlement, elsewhere `aps-environment` in the embedded
provisioning profile (`development` is the sandbox). An iOS app on a device with no profile is an
App Store or TestFlight build, which is always production. A simulator build has neither, so it
reads `nil`; pass `environment: PushEnvironment(server: .sandbox, source: .host)` where the app knows
better.

### The risk, and why a token may go over IPC

The charter's rule "never expose secrets (keychain values, tokens) over IPC" means credentials. A
device token isn't one: it names the device to APNs, and sending it a push also takes the
company's APNs key or certificate, which neither the app nor the sidecar holds. It is still a device
identifier, so the risk is low to medium, and the capability treats it that way. It is off by
default and served only during a session. Outside one the snapshot holds nothing, and under a grant
policy a session whose grant doesn't list `PushRegistrationMirror.pluginID` is served nothing
either.

### Where the token is written

The token is written nowhere but the capability's snapshot file in the app's own directory of the
group's store, and only during a session. The file is rewritten without the token as the session
ends or expires, removed as a gate turns the capability off, and rewritten or removed as the
receiver next starts after a launch killed during a session. The mirror keeps the token in memory;
nothing goes to the defaults, another file, the audit log or a log line.
