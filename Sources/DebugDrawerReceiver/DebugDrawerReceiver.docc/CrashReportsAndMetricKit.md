# Collecting Crash Reports and MetricKit Payloads

Get a dogfooder's crash to the team through the sidecar, without a crash SDK's dashboard.

## Overview

The app keeps the MetricKit payloads it receives, crash diagnostics among them, and serves them to
the sidecar's next session. It is off unless the app enables it. Link `DebugDrawerMetricKit`
(`.product(name: "DebugDrawerMetricKit", package: "DebugDrawer")`), the UI-free half of the
MetricKit plugin, beside the receiver, and enable the capability:

```swift
import DebugDrawerMetricKit
import DebugDrawerReceiver

@MainActor
final class ProductionDiagnostics {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.metricKitPayloads(sessions: sessions))
        try receiver.start()
    }
}
```

### MetricKit alone captures

Making the capability subscribes to `MXMetricManager`, and does nothing else. No signal or
exception handler is installed in the build that ships, so a crash SDK the app uses is undisturbed.
The system writes a crash's `MXCrashDiagnostic` itself and delivers it in a diagnostic payload on a
later launch (on the next one, from iOS 15 and macOS 12), with hangs, CPU and disk-write exceptions
and slow launches. The day's metrics arrive about once a day. The payloads MetricKit still holds
from before are kept as the capability is made.

### Kept in the app, served during a session

Each payload is kept once (the same kind and JSON delivered again adds nothing), the newest ten
(`capacity:`), in the app's own Application Support directory (`directory:`), not the app group's.
A crash that arrives before anyone opens a session therefore waits there across launches.

The sidecar connects to `MetricKitPayloadsMirror.pluginID`. Its `MetricKitPayloadsMirror.Snapshot`
holds the open session's ID and every payload kept, the latest period first. Each payload has its
ID (the same in every session), kind (`.metrics` or `.diagnostics`, where a crash is in
`crashDiagnostics`), period, arrival and JSON. While no session is open the snapshot holds none, and
it empties as the session ends or expires.

Within a session `MetricKitPayloadsMirror.Command.delete(id:)` and `deleteAll` delete the app's
copies, for example once the sidecar has sent them on, and MetricKit delivering one again doesn't
bring it back. Under a grant policy the payloads are served only to a session whose grant lists
`MetricKitPayloadsMirror.pluginID`; a session whose grant doesn't is served its ID and no payloads.

### Bounded

A payload whose JSON is larger than a megabyte once redacted is dropped, so the snapshot holds at
most a megabyte per payload of its capacity.

### Redacted in the app

MetricKit's payloads are the system's measurements: numbers, histograms, stack frames and system
text. The one place the app's own data lands in them is an Objective-C exception's reason, so
`MetricKitRedaction.standard` masks its `composedMessage` and `arguments`, at any depth, before the
payload is kept anywhere, and keeps its `formatString`, the code's own text. `adding(keys:)` masks
more of MetricKit's keys (matched exactly, as MetricKit spells them), and `.none` keeps payloads
whole. A masked value becomes `"[REDACTED]"`.
