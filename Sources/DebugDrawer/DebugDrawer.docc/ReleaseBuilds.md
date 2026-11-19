# Release Builds

What the library leaves in a build without `DEBUG`: stand-ins that keep the app's code compiling
and do nothing.

## Overview

The drawer is for the developers and testers of an app, not its users. Everything that draws
the drawer, watches the app or changes its behavior is compiled only when `DEBUG` is defined, as
it is in Xcode's and SwiftPM's debug configuration. A release build keeps the API a host and its
plugins call, as stand-ins, so the same code compiles in both configurations without
`#if DEBUG` around every line.

### What exists in every build, and what it does there

| API | In release |
|---|---|
| `debugDrawer()` | Returns the view unchanged |
| `DebugDrawer.shared.attach(to:)`, for a `UIWindowScene` or an `NSWindow` | Does nothing |
| `debugLocalPlugin(_:)` | Returns the view unchanged; the plugin is never read |
| `DebugDrawer.shared.registerLocal(_:in:)`, for a `UIWindowScene` or an `NSWindow` | Drops the plugin and returns a token that unregisters nothing |
| ``DebugDrawerPlugin`` and its defaults | Compile; nothing reads a plugin |
| ``DebugDrawerPlugin/setBadge(_:)``, ``DebugDrawerPlugin/clearBadge()``, ``DebugDrawerPlugin/postToast(_:)`` | Do nothing |
| ``DebugDrawer/DebugDrawer/setNoticesMuted(_:forPlugin:)``, ``DebugDrawer/DebugDrawer/isNoticesMuted(forPlugin:)`` | Do nothing; every plugin reads as allowed |
| ``DebugDrawerAction`` | Compiles; there is no search field to offer it |
| ``CaptureBuffer`` | Keeps nothing: appends store nothing and every snapshot is empty |
| The rows, buttons and code views, such as ``DebugDrawerSection`` and ``DebugDrawerKeyValueRow`` | Draw nothing |
| `debugDrawerButtonStyle(_:)`, `debugDrawerFont(_:)` and the other style modifiers | Return the view unchanged |
| ``DebugDrawerReportContributor``, ``DebugDrawerReportUploader``, ``DebugDrawerReport``, ``DebugDrawerRedaction`` | Compile; there is no report and nothing calls them |
| ``DebugDrawer/DebugDrawer`` and its ``DebugDrawer/DebugDrawer/shared`` instance | Registering drops the plugin, toggling opens nothing, and every property keeps its starting value |
| ``DebugDrawer/DebugDrawer/createReport(in:)`` | Throws ``DebugDrawerReport/WriteFailed`` |
| ``AnyDebugDrawerPlugin``, ``HUDLayout``, ``DebugDrawerToast`` | Compile; the drawer holds none |
| ``RedactedText`` | Draws nothing |
| `debugDrawerCopyToClipboard(_:)` | Does nothing |
| The shipped plugins' `install*()` calls, their plugin types and their stores | Install nothing; the stores stay empty and swizzle or intercept nothing |

So the calls that set the drawer up need no `#if DEBUG`:

```swift
DebugDrawer.shared.registerGlobal(CachePlugin())
DebugDrawer.shared.reportUploader = TeamReportUploader(endpoint: reportsEndpoint)
```

A release build can't open the drawer by accident: the stand-in has nothing to open, and the
code that draws the drawer, swizzles or intercepts isn't compiled into it.

### Writing a plugin that compiles in release

Every public API compiles in both configurations, so a plugin needs no `#if DEBUG` of its own; its
body is simply never shown in release.
