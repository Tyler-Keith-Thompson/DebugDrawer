# Changing Tweaks in Production

Let a sidecar change the tweaks marked production-safe in a release build, while every other tweak
stays debug-only.

## Overview

A tweak marked `.productionSafe()` where it is declared can be changed from the sidecar in a release
build. Link `DebugDrawerTweaks` (`.product(name: "DebugDrawerTweaks", package: "DebugDrawer")`),
the UI-free half of the Tweaks plugin, beside the receiver, and enable the capability with the
tweaks a sidecar may change:

```swift
import DebugDrawerTweaks

enum AppTweaks {
    static let backend = Tweak.picker("Backend", key: "backend", default: Backend.production).productionSafe()
    static let newCheckout = Tweak.toggle("New checkout", key: "newCheckout", default: false)
}

receiver.enable(.tweaks(AppTweaks.backend, AppTweaks.newCheckout))
```

### Only production-safe tweaks

The sidecar connects to `TweaksModel.pluginID`, and its `TweaksModel.Snapshot` lists only the
tweaks marked `.productionSafe()` (here `backend`), each with its title, key, control, default and
current value. A `setValue` or `reset` naming any other key, `newCheckout` included, is refused as
`commandRefused(.notExposed)` even inside a session. A value that isn't one of the tweak's (a
removed option, a number outside a stepper's range, a string for a toggle) is refused as
`commandRefused(.malformedCommand)`. Both refusals are logged and audited and change nothing.

### Values persist and reach the app

A change goes into the tweaks' storage (the standard defaults, or the `storage:` you pass, the same
as `installTweaks(storage:)`'s), so `AppTweaks.backend.value` and its `publisher` return it, now and
after a relaunch. In a release build a production-safe tweak reads its stored value only once the
app has made the capability, so make it at startup before reading tweaks. An app that never makes
it reads every tweak's default.

### Persistent by default

Pass `scope: .session(revertWith: .resetAll)` to reset the production-safe tweaks to their defaults
when the session ends instead. Tweaks a session set when the app was killed or quit during it are
reset as the next launch enables the capability, audited as `changeReverted`, so make it at
startup, before the app reads a tweak.
