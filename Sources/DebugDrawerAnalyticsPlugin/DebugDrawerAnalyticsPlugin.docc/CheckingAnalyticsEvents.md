# Checking Analytics Events

List the analytics events the app sends, as it sends them, to check that the right event fired.

## Overview

The Analytics plugin lists the analytics events the app sends, so QA can check that the right
event fired with the right properties. The app records each event where it hands it to its
analytics service:

```swift
import DebugDrawerAnalyticsPlugin

// At startup:
AnalyticsEvents.install()

// Wherever the app sends an event to its analytics service:
AnalyticsEvents.record("checkout_completed", properties: [
    "plan": "pro", "seats": 3, "total": 29.99, "trial": false, "coupon": nil,
    "items": ["sku-1", "sku-2"], "shipping": ["country": "NZ"]
], source: "Segment")

// From an SDK's untyped properties:
let properties: [String: Any] = ["screen": "Settings", "dark_mode": true]
AnalyticsEvents.record("screen_viewed", properties: properties.mapValues(AnalyticsValue.init(converting:)))
```

`AnalyticsEvents` and `AnalyticsValue` exist in every configuration, so the calls need no
`#if DEBUG`. In release they do nothing, and `record` doesn't even evaluate its arguments, unless
a sidecar's session is mirroring analytics events (see "In production" below).

### Recording

In debug builds `record` can be called from any thread or actor and returns at once. Property
values are `AnalyticsValue`s (strings, integers, doubles, Booleans, dates, `nil`, arrays and
objects of them), which literals convert to. `AnalyticsValue(converting:)` reads a value from a
`[String: Any]` as SDKs take them. `source` names the service, for an app that sends to more than
one.

### In the drawer

The plugin keeps the newest thousand events in memory (`install(capacity:)` takes another number),
including those recorded before `install()`, so the events sent while the app launches show too.

The drawer lists them newest first. Each row has the event's name, the time it was recorded to the
millisecond, its source and how many properties it has. The header shows how many events there
are, and a badge counts those that arrived while the list was off screen. The filter matches the
name, the source, and property keys and values, nested ones included. Opening an event shows each
property beside its key and the event's JSON (sorted keys, ISO 8601 dates), with Copy JSON. Export
All shares every event as a `.json` array, and Clear drops them.

Values the redaction rules call sensitive (an `auth_token`, say) are masked on screen until
revealed, and in the copy, the export and the bug report, which carries every event as
`analytics.json`. The plugin runs on every platform the drawer does. tvOS and watchOS have no
pasteboard or share sheet, so there it offers no Copy JSON or Export All.

### In production

`AnalyticsEvents`, `AnalyticsValue` and the sink live in `DebugDrawerAnalytics`, a UI-free module
that `DebugDrawerAnalyticsPlugin` re-exports and a release build links on its own. Through it, a
release build's receiver can mirror the events recorded during a sidecar's session, redacted in
the app; the DebugDrawerReceiver documentation's Mirroring Analytics Events in Production article describes it. In debug builds the drawer
keeps the events as well.
