# Detecting Hangs

Catch each time the main thread gets stuck, with the stack it was stuck on.

## Overview

A hang is the main thread going too long without turning its run loop, so the app can't draw or
take a tap. The Hangs plugin catches each one as it happens and records the stack the thread was
stuck on:

```swift
import DebugDrawerHangDetectorPlugin

// At startup; a stall of the main thread over 250 ms is a hang.
HangDetector.install()

// Or with a threshold of the app's own, which the drawer can change later.
try HangDetector.install(threshold: .milliseconds(100))
```

`HangDetector` exists in every configuration, so the call needs no `#if DEBUG`. In release it
starts nothing.

### How a hang is caught

In debug builds the detector adds an observer to the main run loop, which notes the time at each
turn, and starts a watcher thread that wakes four times per threshold. When the main thread has
been busy since its last turn for longer than the threshold, the watcher suspends it, reads its
registers, walks its frame records into a buffer allocated in advance and resumes it, once per
hang. When the main thread turns its run loop again, the plugin names the frames with `dladdr`,
lists the hang with how long it lasted, raises the plugin's badge and posts a toast ("Main thread
hung for 612 ms"). A hang that ends before the watcher's next wake is listed without a stack.

Some stalls aren't counted:

- the launch, before the main run loop first waits;
- time the whole process spent stopped, at a debugger's breakpoint or suspended in the background;
- a stall while the app is out of sight. On iOS that runs from resigning active until the app is
  active again, so the deactivation, the background, the app switcher's snapshot and the return
  aren't hangs, and a stall that the app resigns active in is dropped whole. A stall in the app's
  own code once it is active again is counted, from becoming active. On the Mac an inactive app is
  still on screen, so only a hidden one (and a Mac Catalyst app in the background) isn't counted.

The `MXHangDiagnostic`s MetricKit delivers, which describe earlier runs, are listed as well, with a
badge but no toast.

### Cost

With no hang, the cost is a clock read and an uncontended lock on each turn of the main run loop,
plus a watcher wake four times per threshold that does the same; `PerformanceTracesOverheadTests`
measures both. The monitor lives in `DebugDrawerHangDetector`, which the plugin re-exports, so a
production build can record hangs for a sidecar too. See the DebugDrawerReceiver documentation's
Recording Hangs and Signposts in Production article.

### In the drawer

The drawer lists the hangs newest first (the newest fifty). Opening one shows its stack,
selectable, with a button that copies it, and marks it seen. The Threshold picker changes the
threshold while the app runs, for this run only. Mark All Seen clears the badge, Clear All forgets
the hangs, and a bug report carries them all in `hangs.txt`.
