# Console Sessions

Keep the lines logged in earlier launches, so the next launch can show what happened before a
crash.

## Overview

On iOS the unified log of the current process holds no lines from an earlier launch. So the
Console keeps the lines logged during a launch, or just before a crash, on disk, and the next
launch can show them. Each line is written as it is captured, as logged. The redaction rules mask
it only when it is copied or added to a report (see the DebugDrawer documentation's
Contributing to Bug Reports article).

### The session file

A launch's session is a file of JSON Lines in Application Support, in the app's folder under
`DebugDrawer/ConsoleSessions`. It starts with a header written at install, holding the start time,
the app's version and the process. After that comes one line per log line, with its time, level,
source, os_log subsystem and category (left out when empty) and text. Lines are appended as they
come, so a crash mid-write costs at most the line being written, which is skipped on reading.
Writing happens in batches on a queue of its own, never on the main actor.

### How many sessions are kept

By default 5 earlier sessions are kept in at most 20 MB. Both are set at install:

```swift
import DebugDrawerConsolePlugin

DebugDrawer.shared.installConsole(sessions: ConsoleSessionPersistence(maxSessions: 3, maxBytes: 5_000_000))
```

At launch the oldest sessions beyond `maxSessions` are deleted, then the oldest ones until the
rest fit in `maxBytes`. That limit is checked again as the current session grows. The current
session is never deleted; a line that would take it past `maxBytes` on its own isn't written.
`ConsoleSessionPersistence.off` writes nothing and deletes what earlier launches kept. To keep
sessions somewhere else, pass a `storage` of your own, a `ConsoleSessionStorage` (append, list,
read and delete).

### The last lines before a crash on macOS

The console reads the app's os_log lines from its unified log every two seconds, so a crash or a
kill can happen before it has read the last ones. On macOS the app may be able to read the
system's log (`OSLogStore(scope: .system)`); an app outside the App Sandbox, run by an
administrator, can. Then the next launch reads those lines from it and adds them to the end of the
earlier session. A launch that starts before the system has taken in a crashed process's last
lines misses them.

While the Mac is busy, one read of the system's log can miss a line the log holds. So the next
launch reads it again, up to four times, until a read holds the session's own last os_log line and
finds nothing the reads before it lacked. It keeps every line any read found. Each read takes one
or two seconds, and listing the earlier sessions waits for them. A line every read missed is still
lost.

Elsewhere a session keeps what its own launch read. A session that kept no line and missed none is
deleted at the next launch.

### Sandboxed Mac apps

In an app signed with the App Sandbox the system's log doesn't open: `OSLogStore(scope: .system)`
throws "Connection to logd failed" (`OSLogError` 10), so the lines are lost as on iOS. A sandboxed
app's debug build can read it with these temporary exceptions in its entitlements. App Review
doesn't accept them, so keep them out of what you ship:

```xml
<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
<array>
    <string>com.apple.logd</string>
    <string>com.apple.logd.admin</string>
    <string>com.apple.logd.events</string>
</array>
<key>com.apple.security.temporary-exception.files.absolute-path.read-only</key>
<array>
    <string>/private/var/db/diagnostics/</string>
    <string>/private/var/db/uuidtext/</string>
</array>
```

### The last lines before a crash on iOS

On iOS, Mac Catalyst included, the os_log lines from up to the last two seconds before a crash are
lost. A process there reads only its own log (`OSLogStore(scope: .currentProcessIdentifier)`), and
at the next launch that log holds none of the earlier process's lines, though the system still has
them. Nothing public reads another process's log on iOS or tells the app about an os_log call as
it is made, and a crash's signal handler can't read the log safely, so the plugin doesn't try.

A line that has to outlive a crash can go through `ConsoleLogSink` (see <doc:BridgingYourOwnLogger>).
Its lines are written to the session as they arrive, not every two seconds. A line logged through
both `os.Logger` and the sink shows twice.

On the simulator, the Mac can show the lost lines for a while after the crash:
`xcrun simctl spawn booted log show --last 5m --predicate 'process == "YourApp"'`.

### Browsing earlier sessions

While an earlier session is kept, the console offers Captured and Previous. Previous shows the
newest earlier session, read-only, with a menu of the others listing each one's start, size, the
app version that wrote it and how many lines it holds. The level filter, search, mutes, time range
and Copy All work on it as they do on the captured lines. Delete deletes it, and Delete All
Sessions deletes every earlier one. The bug report adds the newest earlier session as
`console-previous.txt`.
