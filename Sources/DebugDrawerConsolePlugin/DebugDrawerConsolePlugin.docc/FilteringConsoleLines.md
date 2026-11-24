# Filtering Console Lines

Narrow the log by subsystem, category, pattern and time.

## Overview

Each os_log line shows its subsystem and category before its text, short and quiet
(`feed/networking` for `com.example.feed`'s `networking`).

### Muting and copying lines

A line's context menu, or its edit menu on iOS, can mute its subsystem or its category, copy it
(Copy Line, masked the same way Copy All is), or show the lines from it on. More offers the same
mutes for every subsystem and category shown, Copy All, and a time range: the last 1, 5 or 15
minutes before the newest line.

Mutes are kept across launches in the app's folder in Application Support, under
`DebugDrawer/Console/muted.json`. While mutes hide lines, a note under the log says how many, with
Show and Unmute. A time range adds the same kind of note.

### Regular expressions

The `.*` toggle beside the search field reads the search as a regular expression
(`NSRegularExpression`, ignoring case). While the text isn't a valid expression, the field says
so and the list keeps the last valid search.

### Apple's framework logs

Apple's frameworks log debug and info lines fast enough to push the app's own lines out of the
Console's 2,000 within seconds. So the Console leaves out the debug and info lines of every
subsystem starting with `com.apple.`. Their notice, error and fault lines are kept, as is every
line from the app itself, stdout and stderr. To keep Apple's debug and info lines too, install
with `installConsole(includeSystemDebugLogs: true)`.
