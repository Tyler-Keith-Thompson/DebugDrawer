# Keeping the App Reachable in the Background

Keep the app running while a sidecar's session is open, through only what each platform sanctions,
and let go as the session ends.

## Overview

On iPhone the sidecar and the app take turns in the foreground, and a backgrounded app is suspended
within seconds, so it stops answering on the socket. A `DebugDrawerBackgroundKeeper` keeps it
running while a session is open and lets go as the session ends:

```swift
@MainActor
final class SidecarBackground {
    let keeper: DebugDrawerBackgroundKeeper

    init(sessions: DebugDrawerSessions, socketServer: DebugDrawerSocketServer) {
        keeper = DebugDrawerBackgroundKeeper(sessions: sessions, socketServer: socketServer)
    }

    /// From a Start Debug Session button, before switching to the sidecar.
    func startDebugSession() {
        keeper.startSession(duration: 10 * 60, title: "Debug session", subtitle: "Inspector is connected")
    }
}
```

### Starting a session from the app

While a session is open the keeper holds the platform's short request, whoever opened the session.
`startSession(duration:title:subtitle:)` is for a person's action in the app. It opens a session (or
uses the open one) and, on iOS and iPadOS 26 and later, submits a `BGContinuedProcessingTask`, which
the system shows with the session's progress and a way to stop it.

The task's identifier is `continuedProcessingIdentifierPrefix` (by default the bundle identifier and
`.DebugDrawerSession`) plus the session's ID. List the prefix with a wildcard in the Info.plist of
each configuration that makes a keeper: the debug one for the drawer, and the release one too when
the app's receiver makes one (see "In a release build" below). No `UIBackgroundModes` entry is
needed:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER).DebugDrawerSession.*</string>
</array>
```

### When it lets go

Every request ends as the session ends or expires. The session ends when the last sidecar
disconnects from the socket (not when the app stops its own server), when the person stops the
continued processing task in the system's progress, or when the system expires that task. Nothing
keeps the app running for a sidecar that is gone, and the session's changes revert.
`keeper.request` publishes what is held (`DebugDrawerBackgroundRequest`: `none`, `backgroundTask`,
`continuedProcessing`, `activity`), to show beside the session indicator.

### What each platform allows

| Platform | What the keeper holds | Limits |
|---|---|---|
| iOS, iPadOS 26 and later | From `startSession`: a `BGContinuedProcessingTask`, with the system's progress UI; otherwise a UIKit background task | The task must be submitted from a person's action while the app is in the foreground, and runs at once or not at all (`.fail`): when the system refuses it, the session keeps the background task. The system may end it at any time (the person stopping it, resources, a task that looks stalled): its progress is the session's elapsed time, reported every second whether or not the sidecar sends anything, so an idle sidecar doesn't make it look stalled. The Simulator refuses it ("BGTaskScheduler is not available on this platform"), so check it on a device. |
| iOS, iPadOS before 26; tvOS; visionOS | A UIKit background task (`beginBackgroundTask(withName:expirationHandler:)`) | About 30 seconds once the app is in the background, a handoff rather than a session; no system indicator, so the app's own session indicator is the one shown. When it expires the keeper holds nothing until the app returns to the foreground, then asks again. |
| macOS, Mac Catalyst | A `ProcessInfo` activity (`.userInitiatedAllowingIdleSystemSleep`) | Apps aren't suspended there; the activity keeps App Nap from slowing the app, and lets the Mac sleep when idle. It doesn't expire; no system indicator. |
| watchOS | Nothing | `WKExtendedRuntimeSession` runs only for its own session types (self care, mindfulness, physical therapy, smart alarm), none of which a debug session is, so a backgrounded watch app is suspended as usual. |

The keeper never claims an audio, location or VoIP background mode.

### In a release build

The keeper is part of `DebugDrawerReceiver`, like the sessions, and works in every build. A release
build that links the receiver makes it with `DebugDrawerBackgroundKeeper(sessions:
receiver.sessions)` (there is no socket server to pass). It holds a request only while a session is
open, which the receiver allows only for the capabilities the host enables.
