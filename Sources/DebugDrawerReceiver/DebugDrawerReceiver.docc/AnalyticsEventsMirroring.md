# Mirroring Analytics Events in Production

Mirror the events a release build records to the sidecar during a session, so QA can check
tracking on the build that ships.

## Overview

While a sidecar's session is open, the events the app records through `AnalyticsEvents.record` can
be mirrored to the sidecar. It is off unless the app enables it. Link `DebugDrawerAnalytics`
(`.product(name: "DebugDrawerAnalytics", package: "DebugDrawer")`) beside the receiver. It is the
UI-free half of the Analytics plugin and holds `AnalyticsEvents` and `AnalyticsValue`. Enable the
capability with the redaction rules for the app's events:

```swift
import DebugDrawerAnalytics
import DebugDrawerReceiver

@MainActor
final class ProductionAnalyticsMirror {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        try receiver.enable(.analyticsEvents(
            sessions: sessions,
            redaction: .standard.adding(keys: ["customer_name"], values: [#"\bACCT-\d{6}\b"#])
        ))
        try receiver.start()
    }
}

// Wherever the app sends an event, in every build:
AnalyticsEvents.record("checkout_completed", properties: ["plan": "pro", "seats": 3], source: "Segment")
```

### Only during a session

The sidecar connects to `AnalyticsEventsMirror.pluginID`. Its `AnalyticsEventsMirror.Snapshot`
holds the open session's ID and the events recorded since it opened, oldest first, each with its
place in the session's order, time, name, properties and source.

Nothing recorded before the session opens is kept for it. As the session ends or expires the list
empties and nothing more is mirrored, even an event recorded after the expiry date before the
system's timer fires. The snapshot keeps the session's newest 1,000 events (`capacity:`), and
`AnalyticsEventsMirror.Command.clear` drops those already read. While no session is open, `record`
in a release build evaluates none of its arguments.

Under a grant policy, events are mirrored only to a session whose grant lists
`AnalyticsEventsMirror.pluginID`. A session whose grant doesn't is served its ID and no events, and
nothing recorded during it is kept.

### Redacted in the app

Each event is redacted on the thread that records it, before it is kept anywhere, so no unredacted
value reaches the snapshot, the store's files or the audit log (which never holds an event).

`AnalyticsRedaction.standard` masks the value of any property whose key contains `email`, `phone`,
`token`, `secret`, `password`, `session`, `auth` or `apikey`/`api_key`/`api-key` (ignoring case, at
any depth, and an object or array under such a key whole). It also masks any string value holding
an email address or a JSON Web Token, and an event name or source that a value pattern matches.

`adding(keys:values:)` adds key substrings and regular expressions (`NSRegularExpression` syntax,
ignoring case; an invalid one traps), and `AnalyticsRedaction(keys:values:)` starts from none. A
masked value becomes `"[REDACTED]"`. Phone numbers in free text aren't matched by default, so add a
pattern for the formats your app sends.
