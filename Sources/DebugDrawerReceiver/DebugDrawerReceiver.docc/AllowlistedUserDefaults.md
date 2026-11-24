# Editing Allowlisted UserDefaults in Production

Let a sidecar read and edit the UserDefaults keys the app allowlists, and no other, to try a
production build with a setting changed.

## Overview

A sidecar can switch to another plan, turn tips on or make a page longer, for example. The
capability is off unless the app enables it, and enabled with no key it lists nothing. The app
declares each key with the kind of value it holds:

```swift
import Combine
import DebugDrawerReceiver
import Foundation
import os
import SwiftUI

@MainActor
final class ProductionDefaults {
    private static let logger = Logger(subsystem: "com.example.MyApp", category: "Sidecar")
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver
    private var auditForwarding: AnyCancellable?

    init(container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.userDefaults(
            .choice("plan", title: "Plan", options: ["free", "pro"]),
            .bool("showsTips", title: "Shows Tips"),
            .integer("itemsPerPage", title: "Items per Page", in: 10 ... 100)
        ))
        auditForwarding = sessions.auditEntries.sink { entry in
            for change in entry.changes ?? [] {
                Self.logger.notice("Sidecar changed \(change.key, privacy: .public)")
            }
        }
        try receiver.start()
    }
}

struct TipsBanner: View {
    @AppStorage("showsTips") private var showsTips = false

    var body: some View {
        if showsTips {
            Text("Tip: drag a row to reorder it.")
        }
    }
}
```

### The risk: medium

Whoever holds the sidecar can change any allowlisted value, and with it whatever the app derives
from that value. They can't read or write any other key. The domain is never listed, and a key the
app didn't allowlist is refused as `commandRefused(.notExposed)` and stays as it was.

### Each key with its kind

`DebugDrawerUserDefaultsKey` declares a key as `.string(_:title:maximumLength:)`,
`.integer(_:title:in:)`, `.double(_:title:in:)`, `.bool(_:title:)` or `.choice(_:title:options:)`
(stored as a string). A key reads as its kind only (data or a date stored under a string key reads
as none). A value of another kind, out of the key's bounds, longer than its maximum or not one of
its options is refused as `commandRefused(.malformedCommand)`.

These trap: a key listed twice, an empty key, one of DebugDrawer's own (prefixed `DebugDrawer.` or
`com.debugdrawer.`), a choice without options, and a bound that isn't finite. Write the allowlist in
the app's source.

### Never allowlist a secret

A key's value is shown to the sidecar and written to the audit log with each edit, so allowlist no
tokens, passwords or identifiers of a person.

### What a sidecar sends

The sidecar connects to `DebugDrawerUserDefaults.pluginID` with `DebugDrawerUserDefaults.Snapshot`
(each key's declaration and value, and the keys it edited) and `DebugDrawerUserDefaults.Command`:

- `set(key:value:)` with a `DebugDrawerUserDefaultsValue` (`.string`, `.integer`, `.double`,
  `.bool`);
- `remove(key:)`, which leaves the app reading its registered default;
- `revertAll`.

Until the app enables `.userDefaults(...)`, or while it is disabled or its gate is off, every one of
them is refused, even inside a session.

### Every edit in the audit log

Each edit is audited as `commandApplied` with the key and its value before and after in the entry's
`changes` (`DebugDrawerAuditEntry.Change`: `key`, `oldValue`, `newValue`, `nil` for a key holding no
value of its kind). The session's revert is audited as `changeReverted` with what it put back, so a
host forwarding the log, as `ProductionDefaults` does, keeps what the sidecar changed. Entries of
other capabilities have no `changes`, and the JSON leaves it out.

### For the session, unless the app says otherwise

Before a key's first edit the model records what the key held, in the same defaults
(`DebugDrawer.UserDefaults.originalValues`). As the session ends, expires or a gate turns off, each
edited key is put back exactly as it was, or removed if it held only its registered default. Edits
a session left when the app was killed are put back as the next launch makes the capability, so
make it at startup, before the app reads the keys. `scope: .persistent` keeps the edits until a
sidecar sends `revertAll`.

`DebugDrawerUserDefaults(_:defaults:)` (pass it to `.userDefaults(_:scope:)`) reads the keys of
another suite. The model follows the app's own writes through UserDefaults' change notification.

### In the sidecar

The kit's `DebugDrawerSidecarPlugin.userDefaults` lists the keys with their values, an editor for
each kind (a text field, a number field, a switch or a picker), Remove, and Revert All while any key
is edited.
