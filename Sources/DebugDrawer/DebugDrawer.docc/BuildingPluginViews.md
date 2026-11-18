# Building a Plugin's View

Build a plugin's body from the drawer's rows, buttons and styles, so it looks and reads like the
shipped plugins.

## Overview

The drawer's panel is one surface. A plugin's body is a column of rows, grouped into sections,
ending in a row of actions. Each row pads itself, so they stack with no spacing, lays itself out
again at accessibility text sizes, and labels itself for VoiceOver.

```swift
struct ServerSettingsView: View {
    @State private var usesStaging = false

    var body: some View {
        DebugDrawerSection("Server") {
            DebugDrawerRow("Use staging", systemImage: "server.rack", isOn: $usesStaging)
            DebugDrawerKeyValueRow("Host", value: usesStaging ? "staging.example.com" : "api.example.com")
            DebugDrawerKeyValueRow("API key", value: "k-12345", redacted: DebugDrawerRedaction.mask)
        } footer: {
            Text("Applies to the next request.")
        }
        DebugDrawerActionRow {
            DebugDrawerCopyButton("Copy Host") { usesStaging ? "staging.example.com" : "api.example.com" }
            Button("Reconnect") {}
        } trailing: {
            Button("Sign Out", role: .destructive) {}
                .debugDrawerButtonStyle(.destructive)
        }
    }
}
```

A plugin's body returns a view like this one, which keeps the state the plugin itself can't.
These views exist in every build and draw nothing in release, so a plugin's body compiles
unchanged there.

### Sections and rows

- ``DebugDrawerSection``: a group of rows with an optional heading and a note below them.
- ``DebugDrawerRow``: an icon, a title, details below it and an accessory at the trailing edge,
  such as a status or a switch.
- ``DebugDrawerKeyValueRow``: an inspector row of a label and its value. Pass `redacted:` to
  mask a sensitive value until the eye button beside it reveals it.
- ``DebugDrawerIssueRow``: a severity glyph, a title and its status, a monospaced line and
  details, as in Xcode's issue navigator.
- ``DebugDrawerEmptyState``: a symbol, a title and a line saying how something gets there, where
  a plugin has nothing to list yet.
- ``DebugDrawerGaugeRow``: a measure with a bar meter, as Xcode's debug gauges.
- ``DebugDrawerStackFrameRow``: a frame of a stack trace, the app's own frames marked.
- ``DebugDrawerTypeBadgeRow``: a loaded binary, with a letter badge for its kind, its path and
  its version.

### Actions

- ``DebugDrawerActionRow``: a plugin's push buttons, everyday actions at the leading edge and a
  destructive one apart at the trailing edge. End a plugin's body with one, or put one in a row's
  details for actions on that row.
- ``DebugDrawerCopyButton``: a button that copies the text its closure returns when pressed.
- ``DebugDrawerButtonStyle``, applied with `debugDrawerButtonStyle(_:)`: `primary` for the action
  a row exists for, `secondary` (an action row's default) for the rest, `destructive` for one that
  deletes or resets, `borderless` for an action inside a row, and `plain` for a row that is itself
  the button.

### Values and glyphs

- ``DebugDrawerCodeText``: a path or identifier on one line, cut in the middle until tapped.
- ``DebugDrawerCodeBlock``: a well of code, a log or JSON.
- ``DebugDrawerIssueGlyph`` and ``DebugDrawerIssueCount``: a severity glyph, alone or with a
  count, as in a plugin's header accessory.
- ``DebugDrawerUnreadDot``: the dot beside what hasn't been opened yet.
- ``DebugDrawerSparkline``: a line graph of recent samples.
- ``DebugDrawerSearchableList``: a filter field above a scrolling list of rows; the plugin binds
  the field and passes the rows that match.

### Styles for views a plugin lays out itself

Text and controls a plugin lays out itself take the drawer's look through modifiers that change
nothing in release:

- `debugDrawerFont(_:)` sets text in a ``DebugDrawerTextStyle`` role: title, heading, body,
  label, value, code or secondary.
- `debugDrawerForegroundStyle(_:)` colors it in a ``DebugDrawerForegroundStyle``.
- `debugDrawerValueStyle(_:)` decides whether ``DebugDrawerKeyValueRow``s set their values as
  words or as code (``DebugDrawerValueStyle``).
- `debugDrawerTextFieldStyle()` gives text fields the drawer's look.
- `debugDrawerRowPadding()` pads a row of the plugin's own as much as the drawer's rows.
- `debugDrawerSelected(_:)` draws a view as the selected item of a list.

### Platforms

On tvOS and watchOS, which have no pasteboard, ``DebugDrawerCopyButton`` draws nothing. On tvOS
the button styles take the system's matching style, which shows which button has focus.
