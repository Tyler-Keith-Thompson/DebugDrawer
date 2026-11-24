# Network Sessions

Keep the requests made in earlier launches, so the next launch can show them.

## Overview

The requests made during a launch, or just before a crash, are kept on disk so the next launch
can show them. Each request is written as it completes, and each WebSocket connection as it ends.
The redaction rules are applied first, so a masked header, query item or JSON value never reaches
the disk.

### The session file

A launch's session is a file of JSON Lines in Application Support, in the app's folder under
`DebugDrawer/NetworkSessions`. It starts with a header holding the start time and the app's
version, then one HAR 1.2 entry per line, appended as it comes. A crash mid-write costs at most the
line being written, which is skipped on reading. Writing happens on a queue of its own, never in
the URL protocol's callbacks or on the main actor.

### How many sessions are kept

By default 5 earlier sessions are kept in at most 20 MB. Both are set at install:

```swift
import DebugDrawerNetworkPlugin

DebugDrawer.shared.installNetwork(sessions: NetworkSessionPersistence(maxSessions: 3, maxBytes: 5_000_000))
```

At launch the oldest sessions beyond `maxSessions` are deleted, then the oldest ones until the
rest fit in `maxBytes`. That limit is checked again as the current session grows. The current
session is never deleted; a request that would take it past `maxBytes` on its own isn't written.
`NetworkSessionPersistence.off` writes nothing and deletes what earlier launches kept. To keep
sessions somewhere else, pass a `storage` of your own, a `NetworkSessionStorage` (append, list,
read and delete).

### Browsing earlier sessions

While an earlier session is kept, the log offers Captured and Previous (and Imported, while a file
is imported). Previous shows the newest earlier session, with a menu of the others listing each
one's start, size, the app version that wrote it and how many requests it holds. Its requests are
read-only, like imported ones: Copy cURL and Mock This, but not Resend. Export All exports it as a
HAR file, Delete deletes it, and Delete All Sessions deletes every earlier one.

The bug report adds the newest earlier session as `network-previous.har`. Reset App State keeps
the sessions unless DebugDrawer's own settings are included, as it does with the mocks.
