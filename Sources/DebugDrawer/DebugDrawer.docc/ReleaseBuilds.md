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
| `debugLocalPlugin(_:)` | Returns the view unchanged; the plugin is never read |
| ``DebugDrawerPlugin`` and its defaults | Compile; nothing reads a plugin |
| ``DebugDrawerPlugin/setBadge(_:)``, ``DebugDrawerPlugin/clearBadge()``, ``DebugDrawerPlugin/postToast(_:)`` | Do nothing |
| ``DebugDrawerAction`` | Compiles; there is no search field to offer it |
| The rows, buttons and code views, such as ``DebugDrawerSection`` and ``DebugDrawerKeyValueRow`` | Draw nothing |
| `debugDrawerButtonStyle(_:)`, `debugDrawerFont(_:)` and the other style modifiers | Return the view unchanged |
| ``DebugDrawerReportContributor``, ``DebugDrawerReportUploader``, ``DebugDrawerReport``, ``DebugDrawerRedaction`` | Compile; there is no report and nothing calls them |

### What exists in debug builds only

``DebugDrawer/DebugDrawer`` and its ``DebugDrawer/DebugDrawer/shared`` instance,
``AnyDebugDrawerPlugin``, ``AsyncPluginView``, ``OnDemandPluginView``, ``RedactedText``, the HUD
and toast types, and the clipboard helpers. Code that names them sits under `#if DEBUG`, as the
shipped plugins' `install*()` calls do, since those install the swizzling and interception some
plugins need:

```swift
#if DEBUG
    DebugDrawer.shared.registerGlobal(CachePlugin())
    DebugDrawer.shared.reportUploader = TeamReportUploader(endpoint: reportsEndpoint)
#endif
```

Leaving them out of release builds, rather than giving them stand-ins, means a release build
can't open the drawer by accident: there is nothing to open.

### Writing a plugin that compiles in release

A plugin whose body uses only the API in the first table compiles in both configurations, so it
needs no `#if DEBUG` of its own; its body is simply never built in release. A plugin that uses
debug-only API, such as ``AsyncPluginView``, goes under `#if DEBUG` whole, with the code that
registers or attaches it.
