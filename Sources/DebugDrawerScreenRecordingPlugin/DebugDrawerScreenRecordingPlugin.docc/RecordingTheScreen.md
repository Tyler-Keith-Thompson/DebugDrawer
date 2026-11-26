# Recording the Screen

Record a video of the bug, without the drawer in it.

## Overview

The Screen Recording plugin records the app as a QuickTime movie, started and stopped from the
drawer or from the HUD, and leaves the drawer, its HUD and its toasts out of the movie:

```swift
import DebugDrawerScreenRecordingPlugin

// At startup:
ScreenRecording.install()

// Or keep the newest ten recordings rather than five:
try ScreenRecording.install(capacity: 10)
```

`ScreenRecording` exists in every configuration and does nothing in release, so the call needs no
`#if DEBUG`, and a release build links no AVFoundation through it.

### What is recorded

The plugin draws the app's own windows into each frame, up to 30 a second, instead of recording
the screen, so it asks for no permission. On iOS it draws every window of the scene in front,
sheets and alerts included; on macOS, the content of the main window. The drawer can stay open
while it records and doesn't appear in the movie: its windows, the HUD's and the toasts' among
them, are left out. Pin the plugin to the HUD (Show in HUD) to start and stop it with the drawer
closed. On iOS and Mac Catalyst, Show touches draws a circle where each finger is, in the movie
only. It is off until turned on, and remembered.

### Movies

Movies are H.264, at the window's size up to 1920 pixels on the longer side. They are saved in
`Caches/DebugDrawer/Recordings` (in a Mac app outside the App Sandbox,
`Caches/<bundle identifier>/DebugDrawer/Recordings`), and the newest five (or `capacity`) are
kept. Each is listed with when it started, its length and size, and can be shared or deleted. The
newest is marked In Bug Report and goes into the bug report's Screen Recording folder; any other
can be added.

The movie shows what the app's layers hold when each frame is drawn. An animation Core Animation
runs on its own shows at its end, and Metal, video and web content may draw blank.
