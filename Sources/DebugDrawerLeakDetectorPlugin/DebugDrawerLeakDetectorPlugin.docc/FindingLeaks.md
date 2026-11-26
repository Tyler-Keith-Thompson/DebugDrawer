# Finding Leaks

Flag screens and objects that outlive their use.

## Overview

A retain cycle that keeps a dismissed screen alive shows nothing until memory runs short. The
Leaks plugin flags the app's view controllers that are still alive after their screen was
dismissed, and objects that opt in when more of them are alive than their class allows:

```swift
import DebugDrawerLeakDetectorPlugin

// At startup: watches the app's view controllers.
LeakDetector.install()

// An object that opts in, with one call: one should be alive at a time.
final class ProfileModel {
    init() {
        LeakDetector.trackLifetime(of: self)
    }
}
```

`LeakDetector` exists in every configuration, so the calls need no `#if DEBUG`. In release they do
nothing.

### View controllers

In debug builds `install()` exchanges `viewDidDisappear` on `UIViewController` (`NSViewController`
on macOS) for an implementation that calls the original, then notes a view controller that is
leaving for good. On iOS that is one being dismissed or removed from its container, or one inside
a container that is; on macOS, any whose view leaves its window. At the end of the next turn of
the main run loop, after the autorelease pool of the turn that dismissed it has drained, a view
controller that is still alive and still off screen (neither it nor its outermost container is in
a window or presented) becomes a suspect.

Every decision follows an event: the disappearance, the run loop about to wait, a deallocation.
Nothing waits on a timer. The detector holds no reference to what it watches; an object of its
own, attached to each one, tells it of the deallocation.

Only the app's own classes are watched. The system's (SwiftUI's hosting and presentation
controllers, alerts) are left alone, since their frameworks keep them for reuse. A plain
`UIHostingController<Content>` is a specialization made at run time and isn't watched either; a
subclass of it is.

### Objects that opt in

`trackLifetime(of:maxCount:)` counts an object among the live instances of its class until it
deallocates. While more than `maxCount` are alive, the class is a suspect; `trackLifetime(of:)`
allows one. A `maxCount` below 1 throws `LeakDetector.InvalidMaxCount`. It can be called from any
thread, and before `install()`.

### In the drawer

The plugin lists the suspects by class, most recently flagged first, with how many are alive. It
puts a badge on its header for each and posts a toast ("ProfileViewController is still alive after
it was dismissed"). A suspect that deallocates later, or is shown again, stops being one. Ignore
hides a class for this run, Stop Ignoring brings ignored classes back, and a bug report carries the
suspects in `leaks.txt`. A screen the app keeps on purpose to show again is flagged while it is off
screen; ignore its class.
