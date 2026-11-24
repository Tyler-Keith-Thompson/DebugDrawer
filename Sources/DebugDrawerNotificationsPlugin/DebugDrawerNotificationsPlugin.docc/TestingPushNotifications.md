# Testing Push Notifications

See the device token and the app's notification settings, and send a push without a server.

## Overview

The Notifications plugin shows the APNs device token, the app's notification settings, and its
pending and delivered notifications. It also sends a pasted APNs payload as a local notification,
so the app's handlers can be exercised without a push server. The app passes the token on from its
delegate:

```swift
import DebugDrawerNotificationsPlugin

// At startup:
PushNotifications.install()

// In application(_:didRegisterForRemoteNotificationsWithDeviceToken:):
PushNotifications.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)

// In application(_:didFailToRegisterForRemoteNotificationsWithError:):
PushNotifications.didFailToRegisterForRemoteNotifications(withError: error)
```

A SwiftUI app gets those delegate methods through `@UIApplicationDelegateAdaptor` (or
`@NSApplicationDelegateAdaptor`). `PushNotifications` exists in every configuration, so the calls
need no `#if DEBUG`. In release they do nothing, and the plugin's own code touches nothing of User
Notifications. The binary still links the framework, through `DebugDrawerNotifications`, which the
plugin re-exports and whose push registration capability reads the settings in release.

### What the plugin shows

In debug builds the plugin has these sections:

- APNs device token: the token as hexadecimal with Copy Token, or why registering failed. The
  token is a device identifier, so it is masked under the drawer's redaction rules (the standard
  rules mask any key containing `token`) until the eye button reveals it, and in bug reports. Copy
  Token copies the token itself, for pasting into a push tool. The simulator gives a token to an
  app whose entitlements declare `aps-environment`; on the Mac that entitlement needs a
  provisioning profile.
- Authorization: the status (Allowed, Denied, Provisional, Not Asked and so on), each presentation
  setting (alerts, sounds, badges, lock screen, Notification Center, critical, time sensitive,
  alert style, previews), Request while the user hasn't decided, and Refresh.
- Send a payload: an editor for an APNs payload, checked as it is typed, and a delay (now, 5 or 30
  seconds, long enough to put the app in the background). `aps` gives the alert (a string, or a
  dictionary with `title`, `subtitle` and `body`), `badge`, `sound` (`default`, a file name, or a
  critical sound dictionary), `category`, `thread-id`, `target-content-id`, `interruption-level`
  and `relevance-score`. The whole payload, `aps` and every key beside it, becomes the
  notification's `userInfo`, as the app's handlers would get it from APNs. Notes say what a local
  notification does differently: localization keys show as the keys themselves,
  `content-available` doesn't wake the app in the background, `mutable-content` doesn't run a
  notification service extension, and APNs would refuse a payload over 4 KB. Sending asks for
  authorization first if the user hasn't decided.
- Pending and Delivered, each with its count, newest first. Each request or notification takes one
  line, with its title and the time it was delivered or fires next, and can be removed. Opening one
  shows its subtitle, body, identifier, trigger (after an interval, on a date, at a location) or
  delivery time, category, thread, badge and `userInfo`. Each list shows its newest five until
  Show All, and has Remove All.

### Presentation and refreshing

While the app is in front, the system shows a notification only if the app's
`UNUserNotificationCenterDelegate` asks for a banner in `userNotificationCenter(_:willPresent:)`.
The plugin never takes the delegate, which stays the app's. It reads the center when installed,
each time the app becomes active, after a request or a send, and on Refresh; nothing polls.

To send a real remote notification to the simulator from the Mac instead, `xcrun simctl push
<device> <bundle id> payload.json` takes the same JSON. A bug report carries `notifications.txt`:
the token (masked), the settings, and every pending and delivered notification.

### In production

`NotificationSettings` lives in `DebugDrawerNotifications`, the plugin's UI-free half, which the
plugin re-exports. A release build links that module beside the receiver to show a sidecar the
token, the push environment and the settings during its session. See the DebugDrawerReceiver
documentation's Showing the Push Token for Test Pushes article.
