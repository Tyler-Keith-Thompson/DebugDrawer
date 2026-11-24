# Keeping MetricKit Payloads

Read the system's own measurements on the device that took them.

## Overview

MetricKit delivers the app a day's metrics (launch-time and hang histograms, disk writes, memory,
CPU, exits) about once a day, and diagnostics (crashes, hangs, CPU and disk-write exceptions, slow
launches) as they happen. The MetricKit plugin keeps every payload, so they can be read on the
device that measured them:

```swift
import DebugDrawerMetricKitPlugin

// At startup:
MetricKitPayloads.install()

// A payload from elsewhere, such as one a device exported:
let json = Data(#"{"appVersion": "1.2", "cpuMetrics": {}}"#.utf8)
MetricKitPayloads.add(json: json, kind: .metrics)
```

`MetricKitPayloads` exists in every configuration, so the calls need no `#if DEBUG`. In release
they do nothing.

### Subscribing

In debug builds `install()` subscribes to `MXMetricManager` (macOS reports a subset of the metrics
iOS does), and first keeps the payloads the system still holds from before. MetricKit delivers to
every subscriber, so an analytics SDK, Crash Reports and Hangs can subscribe as well and still get
each payload. `add(json:kind:)` keeps a payload the app has from elsewhere as if MetricKit had
delivered it; the period it covers is read from its `timeStampBegin` and `timeStampEnd`. MetricKit
delivers nothing in the simulator, so the example apps add a sample pair from a button, Add Sample
MetricKit Payloads.

### Storage and the drawer

Each payload is kept once (the same kind and JSON delivered again adds nothing), the newest fifty,
in the app's Application Support directory (`install(directory:)` takes another), so the history
survives relaunches.

The drawer lists them with the latest period first. Each row shows the kind, the period it covers
and a line of what it holds (`App 1.2 (34) · 9 metric groups`, `1 crash · 2 hangs`). The plugin
puts a badge on its header for each payload not yet opened and posts a toast for each new one.
Opening a payload shows its JSON, indented with sorted keys and selectable, with Copy JSON and
Export, which shares it as a `.json` file, and marks it seen. Mark All Seen clears the badge, and
each payload can be deleted, or all of them. A bug report carries every payload as a JSON file.

### In production

`MetricKitPayloadKind` and the subscriber live in `DebugDrawerMetricKit`, a UI-free module the
plugin re-exports. A release build can link it beside the receiver to forward payloads to a
sidecar; the DebugDrawerReceiver documentation's Collecting Crash Reports and
MetricKit Payloads article covers it.
