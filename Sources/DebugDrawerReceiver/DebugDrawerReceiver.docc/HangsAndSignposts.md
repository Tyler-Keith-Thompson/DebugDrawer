# Recording Hangs and Signposts in Production

Get a hang a dogfooder hits on an optimized build to the team with the stack it was stuck on and
the app's own timings beside it.

## Overview

During a sidecar's session the app records the main thread's hitches and hangs, using the Hangs
plugin's monitor, and the intervals the app marks, as `os_signpost` marks them. It is off unless the
app enables it. Link `DebugDrawerHangDetector` (`.product(name: "DebugDrawerHangDetector", package:
"DebugDrawer")`), the UI-free half of the Hangs plugin, beside the receiver. Make the recorder with
the receiver's sessions, enable the capability, and mark the intervals worth timing:

```swift
import DebugDrawerHangDetector
import DebugDrawerReceiver
import Foundation

@MainActor
final class ProductionPerformance {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let traces: PerformanceTraces
    let receiver: DebugDrawerReceiver

    init(container: URL) throws {
        traces = PerformanceTraces(sessions: sessions)
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.performanceTraces(traces))
        try receiver.start()
    }

    func loadFeed(from url: URL) async throws -> Data {
        let interval = traces.beginInterval("Load feed")
        defer { traces.endInterval(interval) }
        return try await URLSession.shared.data(from: url).0
    }
}
```

### The risk: low

Whoever holds the sidecar sees stack traces and timings of the app's own code. No user data is
recorded (an interval's name is a `StaticString`, a literal in the app's code), and nothing the
sidecar sends is executed.

### Off until a sidecar records

Until the app enables `.performanceTraces(_:)`, a command is refused as
`commandRefused(.unknownCapability)`. Once it is enabled, nothing runs until a sidecar sends
`PerformanceTraces.Command.start` in an open session: no run loop observer, no watcher thread, no
interval kept, and `beginInterval(_:)` returns one that records nothing. A session opened for
something else starts nothing either.

### What it records

Each stall of the main thread at least `hitchThreshold` long (100 ms unless the app picks another)
is a `Stall`: `.hitch`, or `.hang` from `hangThreshold` (250 ms). A stall has when it began, how
long it lasted, and the main thread's frames, sampled once it reached the hitch threshold. Each
interval that begins and ends while recording is a `SignpostInterval` with its name, start and
duration. The newest 50 stalls and 500 intervals are kept (`limits:`), and the snapshot counts what
the bounds dropped.

### Stacks from an optimized build

A frame carries its address, its image's file name, the image's UUID (`LC_UUID`) and the address's
offset into the image, plus the nearest symbol the image exports. A stripped App Store build exports
few of its own symbols, so the sidecar shows the app's frames as `MyApp + 0x1c1f0` and the system's
by name. The report's `performance.txt` ends with the binary images, each with its load address and
UUID, so `atos -o MyApp.app.dSYM -l <load address> <address>` names the app's frames with the dSYM
archived for that build.

### For the session, always

As the sidecar sends `stop`, as the session ends or expires, and as the receiver's or the
capability's gate turns off, the observer is removed, the watcher thread ends, and the recording is
deleted (audited as `changeReverted`). The recording lives only in memory and in the capability's
snapshot file in the app's own directory of the store. A file a killed launch left behind is removed
as the next launch enables the capability, so enable it at startup. A sidecar's export is its own
copy, in its report (`Command.export` records it).

### What recording costs

`PerformanceTracesOverheadTests` (`just test-release`) measures it in an optimized build on an
Apple M1 Ultra, with the default thresholds:

- about 0.6 µs added to each turn of the main run loop (about 0.13 µs a checkpoint);
- a watcher wake 40 times a second at about 0.08 µs of work each, about 3 µs of CPU a second;
- for each stall, a few µs with the main thread stopped while its stack is read, then about 15 µs a
  frame on the main actor to name its frames (at most 128);
- about 0.45 µs to begin and end a signpost interval, and 0.06 µs while nothing records.

### In the sidecar

The kit's `DebugDrawerSidecarPlugin.performanceTraces` offers Start Recording, then lists the
stalls, newest first, each opening to its main-thread stack, and the intervals, with Stop and
Delete. Create Report adds `performance.txt`.
