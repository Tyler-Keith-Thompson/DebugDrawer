# ``DebugDrawer``

A slide-in panel of debugging tools for your own app, each tool a plugin, with nothing left in
the builds you ship.

## Overview

The drawer is a panel along the trailing edge of the app's window. Each debugging tool in it is
a plugin: a title, an SF Symbol and a SwiftUI view. The shipped plugins (Console, Network,
Performance and the rest) are libraries of their own, so an app links only the ones it wants,
and an app writes plugins of its own with the same protocol and the same views.

This module is the core: the drawer, the ``DebugDrawerPlugin`` protocol, the views plugins are
built from, and the bug report every plugin can add to. Outside `DEBUG` the drawer doesn't exist,
and the API a host calls compiles to stand-ins that do nothing.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:InstallingInSwiftUI>
- <doc:ReleaseBuilds>

### The Drawer

- ``DebugDrawer/DebugDrawer``
- ``AnyDebugDrawerPlugin``
- ``DebugDrawerToast``
- ``HUDLayout``
- ``debugDrawerOverlayIdentifier``
- ``debugDrawerViewTag``
- ``debugDrawerChromeStartLayerName``
- ``debugDrawerChromeEndLayerName``

### Plugins

- <doc:WritingPlugins>
- ``DebugDrawerPlugin``
- ``DebugDrawerAction``
- ``AsyncPluginView``
- ``OnDemandPluginView``

### Building a Plugin's View

- <doc:BuildingPluginViews>
- ``DebugDrawerSection``
- ``DebugDrawerRow``
- ``DebugDrawerKeyValueRow``
- ``DebugDrawerIssueRow``
- ``DebugDrawerGaugeRow``
- ``DebugDrawerStackFrameRow``
- ``DebugDrawerTypeBadgeRow``
- ``DebugDrawerActionRow``
- ``DebugDrawerIssueGlyph``
- ``DebugDrawerIssueCount``
- ``DebugDrawerUnreadDot``
- ``DebugDrawerCodeText``
- ``DebugDrawerCodeBlock``
- ``DebugDrawerCopyButton``
- ``DebugDrawerSparkline``
- ``DebugDrawerSearchableList``
- ``RedactedText``

### Styles

- ``DebugDrawerButtonStyle``
- ``DebugDrawerTextStyle``
- ``DebugDrawerForegroundStyle``
- ``DebugDrawerValueStyle``

### Bug Reports and Redaction

- <doc:BugReports>
- ``DebugDrawerReportContributor``
- ``DebugDrawerReport``
- ``DebugDrawerReportUploader``
- ``DebugDrawerRedaction``

### Platform Types

- ``PlatformImage``
- ``PlatformColor``
- ``PlatformFont``
- ``debugDrawerCopyToClipboard(_:)``
- ``debugDrawerCopyImageToClipboard(_:)``
