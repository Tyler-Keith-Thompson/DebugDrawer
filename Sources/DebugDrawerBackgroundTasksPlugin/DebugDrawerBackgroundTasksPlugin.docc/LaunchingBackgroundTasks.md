# Launching Background Tasks

Launch a background task, or expire it, without waiting for the system.

## Overview

The Background Tasks plugin lists the task identifiers the Info.plist permits
(`BGTaskSchedulerPermittedIdentifiers`) and the requests waiting in `BGTaskScheduler`. It copies
the LLDB commands that make the system launch a task, or expire it, at once:

```swift
import DebugDrawerBackgroundTasksPlugin

// At startup, after registering the app's own launch handlers:
BackgroundTaskRequests.install()
```

`BackgroundTaskRequests` exists in every configuration, so the call needs no `#if DEBUG`. In
release it does nothing, and the plugin references nothing of BackgroundTasks. macOS has no
`BGTaskScheduler`, so there it adds nothing either.

### What the plugin shows

On iOS, iPadOS and Mac Catalyst the plugin has two sections:

- Permitted Identifiers: each identifier and whether a request for it is pending. Beside it is a
  Schedule button for each kind the `UIBackgroundModes` allow (App Refresh for `fetch`, Processing
  for `processing`), which submits a request that may begin now, and a Copy LLDB Command menu with
  the identifier's launch and expiration commands. A refused request shows why on its row:
  unavailable (the simulator, or Background App Refresh turned off), not permitted, or too many
  pending. A wildcard identifier (`….*`, for continued processing tasks) is listed with what it is
  for, without these buttons. Without the modes the section warns that the system runs no request.
- Pending Requests: each request with its identifier, kind (app refresh or processing, with
  whether it needs network or external power) and earliest begin date, each cancellable, with
  Cancel All and Refresh.

The plugin registers no launch handlers. `BGTaskScheduler` requires the app's own, registered for
every permitted identifier before it finishes launching
(`BGTaskScheduler.shared.register(forTaskWithIdentifier:using:launchHandler:)` in
`application(_:didFinishLaunchingWithOptions:)`).

### Running a task now

To run a task's launch handler now, on a device (the simulator runs no background tasks):

1. Schedule a request for the identifier, from the drawer or from the app's own code.
2. Copy its launch command from the Copy LLDB Command menu beside the identifier:
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.example.refresh"]`
3. Pause the app in Xcode (Debug ▸ Pause, or the pause button in the debug bar), paste the command
   at the `(lldb)` prompt, press Return, and continue the app. The system launches the task as it
   would in the background.
4. To test the expiration handler, pause again while the task runs and paste its expiration
   command, `_simulateExpirationForTaskWithIdentifier:` with the same identifier.

The drawer only copies these commands. The selectors are private API, which the app itself never
calls. The plugin reads the pending requests when installed, each time the app becomes active,
after a Schedule and on Refresh; nothing polls. A bug report carries `background-tasks.txt`: the
background modes, the permitted identifiers and every pending request.
